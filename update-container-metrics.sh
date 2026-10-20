#!/usr/bin/env bash
# Export Docker running status and restart counters for Node Exporter's textfile collector.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="${METRICS_DIR:-$SCRIPT_DIR/node-exporter-textfile}"
mkdir -p "$METRICS_DIR"

tmp="$(mktemp "$METRICS_DIR/.todo_containers.prom.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
  echo '# HELP todo_container_restart_count Docker restart count for the current container instance.'
  echo '# TYPE todo_container_restart_count gauge'
  echo '# HELP todo_container_running Whether a container is currently running (1=yes, 0=no).'
  echo '# TYPE todo_container_running gauge'

  for name in \
    todo-backend todo-frontend todo-prometheus todo-grafana \
    todo-alertmanager todo-node-exporter todo-cadvisor
  do
    if docker inspect "$name" >/dev/null 2>&1; then
      restarts="$(docker inspect --format '{{.RestartCount}}' "$name")"
      running="$(docker inspect --format '{{if .State.Running}}1{{else}}0{{end}}' "$name")"
      printf 'todo_container_restart_count{name="%s"} %s\n' "$name" "$restarts"
      printf 'todo_container_running{name="%s"} %s\n' "$name" "$running"
    fi
  done
} > "$tmp"

chmod 644 "$tmp"
mv -f "$tmp" "$METRICS_DIR/todo_containers.prom"
trap - EXIT
