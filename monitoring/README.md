# Monitoring configuration

This folder contains the non-secret monitoring configuration for Todo Summary Assistant.

- `prometheus.yml` scrapes Prometheus, Spring Boot Actuator, Node Exporter, and cAdvisor. Alerts route to Alertmanager at `alertmanager:9093` on the internal Compose network.
- `alert-rules.yml` defines five alerts: backend down, high EC2 CPU, low available memory, low root-disk space, and high JVM heap.
- `grafana-dashboard.json` is the exportable 11-panel dashboard: EC2 CPU, memory, disk, backend availability, JVM heap, HTTP request rate, HTTP 5xx error rate, average HTTP latency, container uptime, container running status, and Docker restart count.
- `grafana/provisioning/` configures the Prometheus data source and dashboard provisioning.
- `alertmanager.example.yml` is a template only. Copy it to the ignored `monitoring/alertmanager.yml` and set the real Slack Incoming Webhook URL locally.
- `../update-container-metrics.sh` exports Docker running state and restart count to Node Exporter's textfile collector.

## Local Compose startup

1. Ensure the ignored root `.env` contains the local MySQL settings and a strong, unique `GRAFANA_ADMIN_PASSWORD`. Never commit `.env`.
2. Create the local-only Alertmanager config:

   ```bash
   cp monitoring/alertmanager.example.yml monitoring/alertmanager.yml
   ```

   Edit `monitoring/alertmanager.yml` and replace the placeholder URL privately. Do not commit this file or share its contents.
3. Validate the stack:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml config --quiet
   ```

4. On a Linux Docker host, generate the first container metrics file and start the full stack:

   ```bash
   chmod +x update-container-metrics.sh
   ./update-container-metrics.sh
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d --build
   ```

5. Open the frontend at `http://localhost:3000`, Grafana at `http://localhost:3001`, and Prometheus at `http://localhost:9090`. Grafana and Prometheus bind to localhost; Alertmanager and cAdvisor have no published host port.

For automatic Docker restart/running-state metrics on a Linux host, enable cron and schedule the update script every minute, for example:

```cron
* * * * * /absolute/path/to/TodoSummaryAssistant/update-container-metrics.sh >/dev/null 2>&1
```

The script needs permission to run `docker inspect`. On EC2, run it as `ec2-user` after confirming that user can execute Docker commands. If the output directory is changed, set `METRICS_DIR` and update the Node Exporter bind mount to match.

## cAdvisor security and host notes

cAdvisor mounts host system paths and uses `privileged: true` to collect Docker container metrics. It is not published to a host port; keep it on the internal Compose network and use a trusted, pinned image. Its privileges are broad and should be reviewed before production use. Resource limits are configured because the lab EC2 instance has limited RAM.

Node Exporter mounts Linux host `/proc`, `/sys`, and `/`. With Docker Desktop on Windows/macOS, these metrics may represent the Docker Linux VM rather than the physical workstation. The cAdvisor host mounts likewise target the Docker host environment.

The root `docker-compose.yml` is the local application stack with local MySQL. The monitoring overlay adds observability without replacing that base file. The EC2 deployment may use a separate server-side Compose file pointing at private RDS. Keep those deployment files aligned manually or by your deployment automation, and never commit real webhook URLs, credentials, environment files, Terraform state, or private keys.
