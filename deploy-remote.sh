#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_TAG="${1:?Missing image tag}"
DOCKERHUB_NAMESPACE="${2:?Missing Docker Hub namespace}"

cd "$HOME/todo-app"

COMPOSE_FILE="docker-compose.yml"
BACKUP_FILE="docker-compose.yml.previous"
CANDIDATE_FILE="docker-compose.yml.candidate"

BACKEND_IMAGE="${DOCKERHUB_NAMESPACE}/todo-summary-backend:${IMAGE_TAG}"
FRONTEND_IMAGE="${DOCKERHUB_NAMESPACE}/todo-summary-frontend:${IMAGE_TAG}"

health_check() {
    local attempt

    for attempt in $(seq 1 12); do
        if curl --connect-timeout 3 --max-time 8 -fsS \
            http://127.0.0.1:3000/ >/dev/null \
            && curl --connect-timeout 3 --max-time 8 -fsS \
            http://127.0.0.1:3000/api/todos >/dev/null; then
            return 0
        fi

        echo "Health check attempt ${attempt}/12 failed; waiting 5 seconds."
        sleep 5
    done

    return 1
}

rollback() {
    echo "ROLLBACK: restoring previous Compose configuration."

    if [[ ! -s "$BACKUP_FILE" ]]; then
        echo "ROLLBACK FAILED: previous Compose backup is missing."
        return 1
    fi

    if ! cp "$BACKUP_FILE" "$COMPOSE_FILE"; then
        echo "ROLLBACK FAILED: could not restore Compose file."
        return 1
    fi

    if ! docker compose -f "$COMPOSE_FILE" pull; then
        echo "WARNING: previous image pull failed; trying locally available images."
    fi

    if ! docker compose -f "$COMPOSE_FILE" up -d; then
        echo "ROLLBACK FAILED: previous containers could not start."
        return 1
    fi

    if health_check; then
        echo "ROLLBACK SUCCESS: previous application version is healthy."
        return 0
    fi

    echo "ROLLBACK FAILED: previous version is unhealthy."
    echo "Manual intervention is required."
    return 1
}

if [[ ! -s "$COMPOSE_FILE" ]]; then
    echo "DEPLOYMENT ABORTED: Compose file is missing."
    exit 1
fi

# Save the current working configuration before changing image tags.
cp "$COMPOSE_FILE" "$BACKUP_FILE"

# Update only backend and frontend image references.
sed -E \
    -e "s|(^[[:space:]]*image:[[:space:]]*)${DOCKERHUB_NAMESPACE}/todo-summary-backend:[^[:space:]]+|\\1${BACKEND_IMAGE}|" \
    -e "s|(^[[:space:]]*image:[[:space:]]*)${DOCKERHUB_NAMESPACE}/todo-summary-frontend:[^[:space:]]+|\\1${FRONTEND_IMAGE}|" \
    "$COMPOSE_FILE" > "$CANDIDATE_FILE"

if ! grep -Fq "$BACKEND_IMAGE" "$CANDIDATE_FILE" \
    || ! grep -Fq "$FRONTEND_IMAGE" "$CANDIDATE_FILE"; then
    echo "DEPLOYMENT ABORTED: expected image references were not updated."
    rm -f "$CANDIDATE_FILE"
    exit 1
fi

if ! docker compose -f "$CANDIDATE_FILE" config --quiet; then
    echo "DEPLOYMENT ABORTED: candidate Compose configuration is invalid."
    rm -f "$CANDIDATE_FILE"
    exit 1
fi

mv "$CANDIDATE_FILE" "$COMPOSE_FILE"

if ! docker compose -f "$COMPOSE_FILE" pull; then
    echo "DEPLOYMENT FAILED: image pull failed."
    if rollback; then
        echo "Previous version recovered, but this release failed."
    else
        echo "CRITICAL: deployment and rollback both failed."
    fi
    exit 1
fi

if ! docker compose -f "$COMPOSE_FILE" up -d; then
    echo "DEPLOYMENT FAILED: containers could not start."
    if rollback; then
        echo "Previous version recovered, but this release failed."
    else
        echo "CRITICAL: deployment and rollback both failed."
    fi
    exit 1
fi

echo "Waiting for application health checks."

if health_check; then
    echo "DEPLOYMENT SUCCESS: ${IMAGE_TAG} is healthy."
    exit 0
fi

echo "DEPLOYMENT FAILED: new version is unhealthy."
echo "Attempting rollback."

if rollback; then
    # The service recovered, but the new release must remain a failed build.
    exit 1
fi

echo "CRITICAL: deployment and rollback both failed."
echo "Manual intervention is required."
exit 2
