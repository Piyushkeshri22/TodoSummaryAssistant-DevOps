# Monitoring configuration

This directory contains source-controlled, non-secret monitoring configuration for Todo Summary Assistant.

- `prometheus.yml` scrapes Prometheus, the Spring Boot Actuator endpoint, and Node Exporter, and routes alerts to Alertmanager on the Compose network.
- `alert-rules.yml` defines backend availability, high CPU, low available memory, low root-disk space, and high JVM heap alerts.
- `grafana-dashboard.json` is an importable five-panel dashboard (CPU, memory, disk, backend availability, and JVM heap).
- `grafana/provisioning/` configures the Prometheus data source and provisions the dashboard at startup.
- `alertmanager.example.yml` is a template only. Its webhook is a placeholder and must be replaced locally before starting the monitoring overlay.

## Start locally

1. Ensure the local ignored `.env` has the MySQL variables needed by the root Compose file and a strong `GRAFANA_ADMIN_PASSWORD` value. You may copy `.env.example` to `.env`, then fill in local values. Never commit `.env`.
2. Create the Alertmanager secret config locally:

   ```bash
   cp monitoring/alertmanager.example.yml monitoring/alertmanager.yml
   ```

   Edit `monitoring/alertmanager.yml` and replace the placeholder `api_url` with your Slack Incoming Webhook. Protect the file and do not commit it.
3. Validate and start the app plus monitoring overlay:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml config --quiet
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d --build
   ```
4. Open the frontend at `http://localhost:3000`, Grafana at `http://localhost:3001`, and Prometheus at `http://localhost:9090`.

Grafana and Prometheus bind to localhost. Alertmanager has no published host port.

## Host metrics note

Node Exporter mounts Linux host `/proc`, `/sys`, and `/`. This is intended for a Linux Docker host such as the EC2 deployment. With Docker Desktop on Windows or macOS, these metrics may represent the Docker Linux VM rather than the physical host OS.

The root `docker-compose.yml` is the local application stack (including local MySQL); the monitoring overlay adds observability services without changing the app file. For the EC2 deployment, maintain the deployment Compose file and secret files on the server, and keep them aligned with these source-controlled monitoring configs. Never commit a real Alertmanager webhook, credentials, environment files, Terraform state, or private keys.
