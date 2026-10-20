# Monitoring and Operations Guide

## 1. Purpose and scope

This document describes how the Todo Summary Assistant is monitored, which operational signals matter, how alerts are routed, and how the team can identify issues before they become user-facing incidents.

The application consists of a React frontend, a Spring Boot backend, and a MySQL database on private Amazon RDS. The application runs on an EC2 host using Docker Compose. Prometheus collects metrics, Grafana visualizes them, Node Exporter exposes host metrics, and Alertmanager sends notifications to Slack.

## 2. Monitoring architecture

```text
React frontend -----> Spring Boot API -----> Private Amazon RDS (MySQL)
                           |
                           | Spring Boot Actuator / Micrometer
                           v
                       Prometheus <------- Node Exporter (EC2 host metrics)
                           |
                           +----> Grafana dashboard
                           |
                           +----> Alertmanager ----> Slack #all-devops-alerts
```

Prometheus is configured with a 15-second scrape interval for these targets:

- `prometheus`: Prometheus self-monitoring.
- `todo-backend`: Spring Boot metrics at `/actuator/prometheus`.
- `node-exporter`: EC2 host metrics.

Grafana's Prometheus data source uses the internal Compose network URL `http://prometheus:9090`. Prometheus and Grafana are bound to EC2 localhost ports and are intended to be reached through an SSH tunnel. Alertmanager has no published host port.

## 3. Metrics monitored and why

### 3.1 Metrics currently implemented

| Signal | Metric / source | Why it matters | Current view or check |
|---|---|---|---|
| Backend scrape availability | Prometheus `up{job="todo-backend"}` | Detects when Prometheus cannot reach the Spring Boot metrics endpoint; this may indicate a stopped or unhealthy backend. | Grafana **Backend Availability** panel and `TodoBackendDown` alert. |
| EC2 CPU utilization | Node Exporter `node_cpu_seconds_total` | Sustained high CPU can cause slow API responses and reduce capacity. | Grafana **EC2 CPU Usage** panel and `EC2HighCPU` alert. |
| EC2 available memory | Node Exporter `node_memory_MemAvailable_bytes` and `node_memory_MemTotal_bytes` | Low available RAM can cause swapping, latency, or out-of-memory termination. `MemAvailable` is more useful than treating Linux cache as wasted memory. | Grafana **EC2 Memory Usage** panel and `EC2LowMemory` alert. |
| EC2 root filesystem usage | Node Exporter `node_filesystem_avail_bytes` and `node_filesystem_size_bytes` | Low disk space can prevent image pulls, log writes, deployments, or application startup. | Grafana **EC2 Disk Usage** panel and `EC2DiskSpaceLow` alert. |
| JVM heap utilization | Spring Boot Actuator / Micrometer `jvm_memory_used_bytes` and `jvm_memory_max_bytes` | Increasing heap pressure can precede long garbage-collection pauses or an application out-of-memory failure. | Grafana **JVM Heap Usage** panel and `TodoBackendHighJvmHeap` alert. |
| Scrape health of monitoring targets | Prometheus `up` series | Helps distinguish an application problem from a monitoring/exporter problem. | Prometheus **Status → Targets**. |

The current Grafana dashboard contains five panels: EC2 CPU Usage, EC2 Memory Usage, EC2 Disk Usage, Backend Availability, and JVM Heap Usage.

### 3.2 Additional signals recommended for a fuller production dashboard

The assessment also calls out request rate, error rate, latency, container restarts, and uptime. These should be added and verified as available before claiming the dashboard covers them fully:

| Signal | How to measure | Why it matters | Implementation status |
|---|---|---|---|
| HTTP request rate | Spring Boot/Micrometer HTTP server request counters, for example `http_server_requests_seconds_count`, if exposed by this application version | Reveals traffic changes and load trends. A low request rate alone is not necessarily a fault. | Not currently a dashboard panel; verify the series at `/actuator/prometheus` before adding. |
| HTTP error rate | Ratio of 5xx responses to all server requests using the HTTP request metrics | Detects failed requests even when the process is still running. | Recommended follow-up panel/alert; not one of the five current rules. |
| HTTP latency | HTTP request timer metrics; add a histogram/percentile configuration before graphing p95/p99 if the required buckets are not emitted | Detects user-facing slowness before total failure. | Recommended follow-up panel; confirm available series first. |
| Container restarts and container-level CPU/memory | Docker/container metrics, typically via cAdvisor or an equivalent exporter | Helps identify crash loops and isolate a resource-heavy container. | Not currently collected by Prometheus. `docker stats --no-stream` and `docker compose ps` are manual operational checks. cAdvisor is optional and should be evaluated against this EC2 instance's limited RAM. |
| Database connectivity and health | Backend database connection/error logs and readiness checks; RDS status, connections, CPU, storage, and failover events in AWS CloudWatch | A running API can still fail when the database is unavailable or exhausted. | Database runs on private RDS. Check application logs and RDS/CloudWatch; RDS metrics are not currently scraped by this Prometheus configuration. |
| Deployment health | Jenkins test/build/deploy output and post-deployment HTTP smoke checks | Confirms whether a new release is healthy and supports rollback when health checks fail. | Checked by the Jenkins deployment pipeline. |

To avoid overstating current coverage, request/error/latency and container-restart panels should be recorded as planned improvements until they are implemented and verified.

## 4. Critical logs and their operational value

| Log source | What to look for | Where to inspect |
|---|---|---|
| Spring Boot backend | Exceptions, stack traces, failed DB connections, connection timeouts, API failures, startup errors, out-of-memory or repeated restarts | `docker logs --tail 100 todo-backend` |
| React/Nginx frontend | Nginx startup/configuration errors, upstream connection failures, HTTP 4xx/5xx patterns, failed proxy requests to the backend | `docker logs --tail 100 todo-frontend` |
| Prometheus | Invalid configuration or alert-rule files, scrape errors, target changes, storage errors, missed data collection | `docker logs --tail 100 todo-prometheus`; also check **Status → Targets** and **Alerts**. |
| Alertmanager | Invalid routing configuration, webhook delivery failures, retries, rejected notifications | `docker logs --tail 100 todo-alertmanager` |
| Grafana | Datasource errors, failed Prometheus queries, provisioning or dashboard-loading errors | `docker logs --tail 100 todo-grafana` |
| Node Exporter | Exporter startup failures or collector errors | `docker logs --tail 100 todo-node-exporter` |
| Jenkins | Test/build failures, image push failures, SSH/deployment failures, failed post-deployment health checks, rollback outcome | Review the relevant Jenkins build console output. |
| MySQL on RDS | Database availability, restarts/failovers, storage pressure, connection exhaustion, and MySQL errors | Review RDS events and configured CloudWatch/RDS logs; inspect backend logs for connection errors. |
| EC2/Docker host | Memory pressure, swap use, disk exhaustion, Docker daemon problems, host restarts | `free -h`, `df -h /`, `docker system df`, `docker stats --no-stream`; review EC2 system logs/CloudWatch where enabled. |

Capture the time of an incident and correlate application, Jenkins, Prometheus, Alertmanager, and AWS events. Avoid putting credentials, authorization headers, database passwords, or webhook URLs into logs or shared incident notes.

Useful container commands:

```bash
docker compose ps
docker logs --tail 100 todo-backend
docker logs --tail 100 todo-frontend
docker logs --tail 100 todo-prometheus
docker logs --tail 100 todo-alertmanager
docker logs --tail 100 todo-grafana
```

## 5. Alerts that matter

The five current Prometheus rules are:

| Alert | Condition | Wait before firing | Priority and response |
|---|---|---:|---|
| `TodoBackendDown` | `up{job="todo-backend"} == 0` | 1 minute | **Critical:** check backend container health/logs, RDS connectivity, and whether the Prometheus target is reachable. Restore service or roll back a bad deployment. |
| `EC2HighCPU` | Average EC2 CPU utilization is above 85% | 5 minutes | **Warning:** inspect CPU trends and `docker stats`; correlate with traffic, deployment activity, and application logs. Escalate if sustained or users are affected. |
| `EC2LowMemory` | Host available memory is below 15% | 5 minutes | **Warning:** check `free -h`, swap usage, and container memory. Investigate heap growth or resource pressure; consider reducing workload or resizing the instance if persistent. |
| `EC2DiskSpaceLow` | Available space on `/` is below 15% | 5 minutes | **Warning:** inspect `df -h /` and `docker system df`; identify safe cleanup candidates before deleting anything. Preserve volumes and rollback images. |
| `TodoBackendHighJvmHeap` | JVM heap usage exceeds 85% of the reported maximum | 5 minutes | **Warning:** inspect JVM heap trends and backend logs; look for sustained growth, garbage-collection pressure, or memory leaks. |

Alertmanager groups alerts by alert name and job, waits briefly before the first notification, groups subsequent notifications, and repeats reminders at a longer interval. Firing and resolved notifications are enabled for Slack. The `SlackWebhookTest` and temporary `SlackPipelineTest` notifications were successfully received; the temporary Prometheus test rule was subsequently removed.

## 6. What should not alert (noise reduction)

Not every metric change is an incident. The alert design intentionally focuses on sustained failures and resource pressure rather than every short-lived fluctuation.

Avoid paging or sending a Slack alert for:

- A brief CPU spike during image pulls, application startup, or deployment that clears before the five-minute threshold.
- One failed scrape or a short network hiccup; the backend rule waits one minute before firing.
- High Linux `used` memory by itself. Linux uses spare RAM for cache; alert on sustained low `MemAvailable` instead.
- Low request volume when no traffic is expected. Low traffic should only alert if a known service-level expectation or synthetic availability check is added.
- A single 404 or isolated client-side validation error. If 4xx/5xx alerting is introduced, use an appropriate rate/ratio and duration rather than one event.
- A single slow request. For latency alerts, use a time window and an agreed threshold/percentile after latency histograms are verified.
- Every successful deployment or every request. Use Jenkins deployment status for releases and alert only when post-deploy health checks fail.
- Repeated copies of the same alert. Group related alerts, deduplicate notifications, and use a repeat interval rather than sending a message for every scrape.

Review thresholds against normal usage once representative traffic and longer-term data are available. Thresholds are initial operational choices, not universal values. Planned maintenance can also be handled with silences or inhibition rules if the project grows; these are not currently configured.

## 7. How issues are detected early

1. **Frequent collection:** Prometheus scrapes the configured targets every 15 seconds, so target failures and metric changes become visible quickly.
2. **Trend visualization:** Grafana allows the operator to see CPU, available memory, disk use, backend reachability, and JVM heap trends instead of relying on a single point-in-time check.
3. **Sustained-condition alerting:** CPU, memory, disk, and heap conditions must remain above/below their thresholds for five minutes before firing. This reduces noise from brief spikes. Backend scrape failure has a one-minute wait.
4. **Slack delivery:** Alertmanager routes firing and resolved notifications to `#all-devops-alerts`. End-to-end delivery was verified with a temporary test alert.
5. **CI/CD checks:** Jenkins runs backend tests and frontend build checks before deployment, then checks the application endpoints. A failed deployment health check triggers the pipeline's configured rollback path.
6. **Operational checks:** When investigating an alert, combine Prometheus targets/rules with container state, logs, `free -h`, `df -h /`, and `docker stats --no-stream`.
7. **Database visibility:** Investigate backend DB connection errors alongside RDS status, events, connections, CPU, and storage in AWS CloudWatch. These RDS metrics are not currently part of the Prometheus dashboard.

### Incident triage order

1. Confirm user impact and whether the frontend and `/api/todos` endpoint respond.
2. Check `docker compose ps` and inspect backend/frontend logs.
3. Check Prometheus **Status → Targets**, current alert state, and recent metric trends.
4. Check host RAM/swap, disk, and container usage.
5. Check RDS health and database connection errors.
6. If the issue started after deployment, inspect the Jenkins console output and use the documented rollback process.
7. After recovery, confirm the relevant target is `up` and that a resolved notification is delivered.

## 8. Access and security

- Grafana and Prometheus are bound to EC2 localhost ports; access them through an SSH tunnel using the current EC2 public IP.
- Alertmanager listens only on the internal Docker network and has no public host-port mapping.
- Keep the Slack Incoming Webhook URL in the protected server-side `alertmanager.yml`; do not commit that file or share its contents. The webhook is a credential and must be rotated if exposed.
- Keep `.env`, `grafana.env`, Terraform state, private keys, database credentials, API keys, and tokens out of Git.
- Restrict SSH and administrative access to trusted sources; do not open Prometheus or Alertmanager to the public internet.
- Use environment variables or a secret manager for sensitive application configuration.

## 9. Operational commands

Run these commands from the EC2 application directory (`~/todo-app`).

Check services:

```bash
docker compose ps
```

Check Prometheus readiness, targets, rules, and Alertmanager connection:

```bash
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:9090/api/v1/targets
curl -fsS http://localhost:9090/api/v1/rules
curl -fsS http://localhost:9090/api/v1/alertmanagers
```

Check backend health and application metrics from inside the Compose network:

```bash
docker exec todo-frontend wget -qO- http://backend:8080/actuator/health
docker exec todo-frontend wget -qO- http://backend:8080/actuator/prometheus
```

Check host and Docker resources:

```bash
free -h
df -h /
docker system df
docker stats --no-stream
```

## 10. Known limitations and follow-up work

- The current Grafana dashboard contains five panels: CPU, memory, disk, backend availability, and JVM heap.
- Request rate, error rate, latency, and container restart panels are part of the recommended next iteration to align the dashboard with the full monitoring assessment. Verify the relevant metrics/exporter first; cAdvisor is not currently installed.
- AWS RDS metrics are checked through AWS RDS/CloudWatch and are not currently scraped by Prometheus.
- Alert rules and Slack delivery have been tested. Alertmanager is configured for firing and resolved messages; external email is not configured.
- The current EC2 instance has limited memory. Monitor RAM and swap carefully before adding more containers or collectors.

## 11. Operational checklist

- [ ] All expected Docker Compose services are running.
- [ ] Prometheus reports `prometheus`, `todo-backend`, and `node-exporter` as `up`.
- [ ] All five permanent alert rules are loaded and evaluating.
- [ ] Prometheus reports one active Alertmanager.
- [ ] A test notification has been received in Slack.
- [ ] Grafana shows the five implemented dashboard panels.
- [ ] EC2 available memory, swap use, and root disk space are checked regularly.
- [ ] Deployment health checks and rollback behavior are reviewed after a failed or risky release.
- [ ] No secrets or generated state files are committed to the repository.

## 12. Summary

This design combines metrics, logs, sustained-condition alerts, CI/CD health checks, and Slack notifications to detect operational problems early while avoiding noise from short-lived or expected behavior. As the service grows, the next monitoring improvements are HTTP request/error/latency panels, container-level metrics, and more complete RDS observability.
