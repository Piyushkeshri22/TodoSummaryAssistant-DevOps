# Failure Scenarios and Rollback Plan

This document describes how to respond to deployment, application, infrastructure, and secret-management failures in the Todo Summary Assistant project.

## 1. A faulty version is deployed

**Detection:** Jenkins build/test output, the post-deployment HTTP health check, backend logs, and the Prometheus `TodoBackendDown` alert.

**Response and rollback:**

1. Stop further deployments and identify the failing Jenkins build and image tag.
2. Review Jenkins deployment output and `docker logs --tail 100 todo-backend`.
3. Restore the previously known-good image tags and Compose configuration from the deployment backup maintained by the pipeline. Confirm the exact backup filename on the EC2 host before restoring it.
4. Pull the known-good images and recreate the application containers with `docker compose up -d` from the deployment directory.
5. Verify the frontend, `/api/todos`, backend health, and Prometheus target are healthy.
6. Record the failing build, cause, rollback result, and follow-up action.

Use immutable image tags and retain the previous known-good image so that rollback does not depend on rebuilding an older version.

## 2. The application crashes after deployment

The backend and frontend Compose services use `restart: unless-stopped`, which restarts a container when its main process exits. A Docker health check or an `unhealthy` status by itself does not guarantee that Compose will restart the container; therefore, also monitor application health and scrape status.

1. Run `docker compose ps` and inspect `docker logs --tail 100 todo-backend` or `docker logs --tail 100 todo-frontend`.
2. Verify database reachability, environment variables, startup errors, and available host memory.
3. Check Prometheus targets and the `TodoBackendDown` alert.
4. If the crash follows a new release, roll back to the last known-good image tag.
5. Run the application health checks and confirm the alert resolves.

## 3. Jenkins is unavailable

Jenkins being unavailable should not prevent an operator from performing a controlled emergency recovery, provided SSH access and the EC2 instance remain available.

1. Connect to EC2 using the approved SSH key and restricted security group rule.
2. Inspect the deployment directory, Compose file, image tags, and deployment backups.
3. Use a previously published, known-good Docker image tag; do not make an unreviewed code change directly on the server.
4. Restore the known-good Compose configuration if needed, then run `docker compose pull` and `docker compose up -d`.
5. Verify frontend and backend health, Prometheus targets, and Slack notifications.
6. When Jenkins is restored, reconcile the manual recovery with source control and document what changed.

## 4. A secret is leaked

Treat a leaked secret as compromised even if it is deleted from the latest commit.

1. Revoke or rotate the exposed credential immediately. For example, regenerate the Slack Incoming Webhook, rotate database credentials or third-party API keys, and rotate registry/Jenkins credentials as applicable.
2. Update the value in the protected server-side configuration or CI credential store, then safely restart/reload the dependent service.
3. Inspect Git history, build logs, artifacts, and access logs for further exposure.
4. Remove the secret from repository history where appropriate, but do not treat history cleanup as a substitute for rotation.
5. Review permissions and add/update secret-scanning protections.

Never commit `.env`, `grafana.env`, `alertmanager.yml` containing a real webhook, Terraform state, private keys, or access tokens.

## 5. The EC2 instance fails

1. Check EC2 instance status checks, system logs, and relevant CloudWatch metrics/events.
2. If the instance is unrecoverable, recreate or replace it using the Terraform configuration and the approved SSH key.
3. Reapply the required security group rules and ensure RDS remains private and accepts connections only from the application security group.
4. Recreate the deployment directory and protected environment files from the approved secret source. Do not rely on secrets stored only on the failed instance.
5. Deploy the last known-good container images and validate the application, monitoring targets, and Slack notifications.
6. If the public IP changes, update deployment settings and any origin/CORS or allow-list configuration that depends on the old IP.
7. Confirm RDS data remains available before making any database recovery changes. Do not destroy or replace RDS as part of an EC2 recovery unless that is explicitly intended.

## 6. RDS becomes unavailable

**Impact:** The Spring Boot backend may fail to start or return errors for operations that require MySQL. The frontend may still load, but database-backed functions will not work correctly.

1. Inspect backend logs and RDS status/events/metrics in AWS.
2. From EC2, verify DNS resolution, connectivity to the RDS endpoint on port 3306, database security group rules, and credentials.
3. Check whether the issue is a transient AWS event, capacity/connection exhaustion, a security group change, or invalid configuration.
4. Restore connectivity or service availability before attempting destructive changes.
5. If recovery from data corruption or a deleted database is necessary, restore a suitable RDS snapshot or point-in-time recovery to a new database instance, validate the recovered data, and update the application configuration securely.
6. Multi-AZ failover and point-in-time recovery depend on the actual RDS configuration and retention settings; verify those settings rather than assuming they are enabled.

## Post-recovery verification checklist

- [ ] Frontend responds successfully.
- [ ] Backend health endpoint reports healthy and `/api/todos` responds.
- [ ] All expected Prometheus scrape targets report `up`.
- [ ] The five permanent Prometheus alert rules are loaded.
- [ ] Prometheus reports an active Alertmanager.
- [ ] A test notification reaches the Slack alert channel when a notification test is needed.
- [ ] Logs show no repeated crashes or database connection errors.
- [ ] The incident, cause, remediation, and preventive action are documented.
