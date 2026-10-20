# Monitoring and Operations Guide

## 1. Purpose and scope

This guide explains which metrics are monitored and why, which logs are operationally important, which events warrant alerts, which events should not alert to avoid noise, and how problems are detected early for Todo Summary Assistant.

The application has a React frontend, Spring Boot backend, and MySQL database on private Amazon RDS. Docker Compose runs the application and monitoring stack on EC2. Prometheus collects metrics; Node Exporter provides host and textfile metrics; cAdvisor provides container metrics; Grafana visualizes metrics; Alertmanager sends notifications to Slack.

## 2. Monitoring architecture

```text
React/Nginx frontend ---> Spring Boot API ---> Private Amazon RDS (MySQL)
                               |
                               +-- Actuator / Micrometer HTTP and JVM metrics
                                            |
                   EC2 host metrics ---> Node Exporter <--- textfile collector
                                            ^                     ^
                                            |                     |
                                      Prometheus <--- Docker restart/running script
                                            ^
                                            +--- cAdvisor container metrics
                                            |
                                            +---> Grafana dashboard
                                            |
                                            +---> Alertmanager ---> Slack #all-devops-alerts
```

Prometheus scrapes every 15 seconds:

- `prometheus`: Prometheus self-metrics.
- `todo-backend`: Spring Boot metrics at `/actuator/prometheus`.
- `node-exporter`: EC2 CPU, memory, filesystem and textfile metrics.
- `cadvisor`: container metrics including container start time.

The Docker metrics script writes `todo_container_running` and `todo_container_restart_count` gauges to `node-exporter-textfile/todo_containers.prom`. Cron runs that script once per minute on the EC2 host. Prometheus scrapes the metrics through Node Exporter. Restart count is for the current Docker container instance and resets when that container is recreated.

Grafana's Prometheus data source uses `http://prometheus:9090` on the internal Compose network. Prometheus and Grafana are bound to the EC2 localhost interface; access them through an SSH tunnel. Alertmanager and cAdvisor have no published host port.

## 3. Metrics monitored and why

### 3.1 Implemented dashboard metrics

| Signal | Source / query | Why it matters | Dashboard panel |
|---|---|---|---|
| EC2 CPU utilization | Node Exporter `node_cpu_seconds_total` | Sustained CPU saturation can slow API responses and reduce capacity. | EC2 CPU Usage |
| EC2 memory pressure | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | Low available memory risks swapping, latency and OOM termination. `MemAvailable` is more useful than raw Linux `used` memory. | EC2 Memory Usage |
| Root filesystem usage | `node_filesystem_avail_bytes` and `node_filesystem_size_bytes` for `/` | Low disk space can block image pulls, log writes and deployment. | EC2 Disk Usage |
| Backend scrape availability | `up{job="todo-backend"}` | Detects when the metrics endpoint is unreachable; this can indicate a stopped backend or a scrape/network issue. | Backend Availability |
| JVM heap utilization | `jvm_memory_used_bytes` divided by `jvm_memory_max_bytes` for heap | Sustained heap pressure can precede GC pauses and an OOM failure. | JVM Heap Usage |
| HTTP request rate | `rate(http_server_requests_seconds_count[5m])`, excluding Actuator paths | Reveals request load trends. Low traffic alone is not a fault unless traffic is expected. | HTTP Request Rate |
| HTTP 5xx error rate | 5xx request rate divided by total request rate | Detects server-side failures even when the process is still running. | HTTP 5xx Error Rate |
| Average HTTP latency | Rate of cumulative duration divided by request rate | Reveals slow-response trends. This is an average, not p95/p99 latency. | Average HTTP Response Latency |
| Container uptime | `time() - container_start_time_seconds` from cAdvisor | Shows the time since each current container started and helps correlate restarts with deployments or crashes. | Container Uptime |
| Container running state | `todo_container_running` from Node Exporter textfile collector | Shows whether each named container is running (`1`) or stopped (`0`) at the last script update. | Container Running Status |
| Docker restart count | `todo_container_restart_count` from Docker inspect through the textfile collector | Highlights restarts of the current container instance. It is not a historical total across removed/recreated containers. | Docker Container Restart Count |

The source-controlled Grafana dashboard JSON contains these 11 panels.

### 3.2 Additional useful signals

- **Latency percentiles:** `/actuator/prometheus` exposed request count and sum metrics during verification, but no histogram buckets were observed in that check. Enable and verify histogram buckets before claiming p95/p99 latency.
- **RDS:** Review RDS status, events, connections, CPU, storage and CloudWatch metrics. RDS metrics are not currently scraped directly by this Prometheus configuration.
- **HTTP 4xx rate:** Useful for diagnosis, but isolated 4xx responses generally should not alert unless tied to a clear service objective.
- **Container CPU/memory:** cAdvisor exposes these metrics, though the current JSON dashboard does not yet have dedicated per-container CPU/memory panels.

## 4. Critical logs

| Log source | Critical patterns | Where to inspect |
|---|---|---|
| Spring Boot backend | Startup failure, exceptions, failed DB connections, API errors, timeouts, OOM/GC symptoms | `docker logs --tail 100 todo-backend` |
| React/Nginx frontend | Nginx configuration/startup errors, upstream connection failure, repeated HTTP 5xx | `docker logs --tail 100 todo-frontend` |
| Prometheus | Invalid YAML/rules, scrape failures, target transitions, storage errors | `docker logs --tail 100 todo-prometheus`; Status → Targets and Alerts |
| Alertmanager | Invalid receiver/route, Slack webhook delivery error or repeated retries | `docker logs --tail 100 todo-alertmanager` |
| Grafana | Datasource, PromQL, dashboard provisioning or query errors | `docker logs --tail 100 todo-grafana` |
| Node Exporter | Exporter startup or collector errors; missing textfile metrics | `docker logs --tail 100 todo-node-exporter` |
| cAdvisor | Failure reading Docker/container information or repeated collector errors | `docker logs --tail 100 todo-cadvisor` |
| Jenkins | Test/build/image push/SSH deployment/health check and rollback errors | Jenkins build console output |
| RDS/MySQL | Availability/failover events, exhausted connections, storage pressure, database errors | RDS events/CloudWatch and correlated backend logs |
| EC2/Docker host | Memory or disk pressure, Docker daemon failure, host restart | `free -h`, `df -h /`, `docker system df`, `docker stats --no-stream`, AWS system logs/CloudWatch where enabled |

Correlate timestamps across Jenkins, application logs, Prometheus and AWS events. Do not log or share database credentials, access tokens, authorization headers or Slack webhook URLs.

## 5. Alerts that matter

These five Prometheus rules are implemented and configured to notify through Alertmanager to Slack. A rule can be inactive when its condition is healthy.

| Alert | Condition | Wait | Priority and action |
|---|---|---:|---|
| `TodoBackendDown` | `up{job="todo-backend"} == 0` | 1 minute | Critical: inspect backend logs, RDS connectivity and target health; restore service or roll back a bad release. |
| `EC2HighCPU` | Average host CPU > 85% | 5 minutes | Warning: inspect `docker stats`, host processes and request/deployment activity. |
| `EC2LowMemory` | Available host RAM < 15% | 5 minutes | Warning: inspect `free -h`, swap and container/JVM memory. Reduce workload or resize if persistent. |
| `EC2DiskSpaceLow` | Available space on `/` < 15% | 5 minutes | Warning: check `df -h /` and `docker system df`; remove only verified unused resources and preserve rollback images/volumes. |
| `TodoBackendHighJvmHeap` | JVM heap > 85% of reported maximum | 5 minutes | Warning: inspect heap trends, GC pressure and backend logs. |

Alertmanager groups and deduplicates notifications, delays the initial message briefly, sends firing and resolved notifications, and repeats reminders on a longer interval. Slack delivery was end-to-end tested with a temporary alert, which was then removed.

## 6. What should not alert (noise reduction)

Avoid notifications for every metric movement. These situations generally should not trigger a page:

- A short CPU spike during deployment or image pulls that clears before the alert's `for` duration.
- One brief scrape failure or short network hiccup; the backend alert waits one minute.
- High Linux `used` memory by itself; Linux uses spare RAM for cache. Alert on sustained low `MemAvailable` instead.
- Low request volume when no traffic is expected, unless a future synthetic monitor or service-level objective makes it meaningful.
- A single 404 or isolated client validation failure. If alerting on 4xx/5xx, use a rate/ratio and duration appropriate to impact.
- One slow request. A latency alert should use a sustained window and an agreed threshold/percentile after histogram metrics are enabled.
- Each successful deployment or every request. Use Jenkins status and post-deployment smoke checks; alert when checks fail.
- Duplicate messages for the same condition. Use Alertmanager grouping and repeat intervals.

The current thresholds are initial lab values. Revisit them after observing representative traffic. Silences and inhibition rules may help during planned maintenance as the project grows, but are not currently configured.

## 7. How issues are detected early

1. **15-second collection:** Prometheus refreshes metrics frequently enough to expose target failures and changing resource trends promptly.
2. **Trend graphs:** Grafana shows CPU, memory, disk, backend availability, heap, request rate, 5xx rate, average latency, container uptime/status and restart count.
3. **Sustained thresholds:** CPU, memory, disk and JVM heap alerts wait five minutes; backend down waits one minute, reducing noise from transient conditions.
4. **Slack:** Alertmanager routes firing and resolved alerts to `#all-devops-alerts`. Delivery was tested successfully.
5. **CI/CD health checks:** Jenkins tests and builds before deployment and runs post-deployment checks; failed checks can trigger the pipeline rollback logic.
6. **Container metrics:** cAdvisor supplies container series, while the once-per-minute Docker inspect script provides running state and restart count.
7. **Database correlation:** Check backend connection errors together with RDS health/events/CloudWatch metrics, as RDS metrics are not directly scraped into Prometheus yet.

### Incident triage order

1. Confirm user impact by checking the frontend and `/api/todos` endpoint.
2. Check `docker compose ps` and backend/frontend logs.
3. Check Prometheus **Status → Targets**, loaded rules, alert states and recent trends.
4. Inspect `free -h`, swap use, `df -h /`, and `docker stats --no-stream`.
5. Check RDS health and database errors.
6. If the issue began after deployment, inspect Jenkins console logs and use `FAILURE_AND_ROLLBACK.md`.
7. After recovery, confirm targets are healthy and the corresponding alert resolves.

## 8. Access and security

- Prometheus and Grafana are bound to EC2 localhost ports and should be accessed via an SSH tunnel.
- Alertmanager and cAdvisor have no published host port.
- cAdvisor uses privileged host access and read-only host mounts to inspect Docker containers. Keep it on the trusted internal network, pin its image, and review these privileges before production use.
- Keep the real Slack Incoming Webhook in a protected, ignored `monitoring/alertmanager.yml` on the server. Never commit or share the file contents; rotate the webhook if exposed.
- Keep `.env`, `grafana.env`, Terraform state/tfvars, private keys, database credentials, API keys and tokens out of Git.
- Restrict SSH and administrative access to trusted source addresses. Never expose Prometheus or Alertmanager to the public internet.

## 9. Operational commands

Run these on EC2 from `~/todo-app`.

```bash
# Services and resource pressure
docker compose ps
free -h
df -h /
docker system df
docker stats --no-stream

# Prometheus health, targets, rules and Alertmanager
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:9090/api/v1/targets
curl -fsS http://localhost:9090/api/v1/rules
curl -fsS http://localhost:9090/api/v1/alertmanagers

# Backend health and metrics
docker exec todo-frontend wget -qO- http://backend:8080/actuator/health
docker exec todo-frontend wget -qO- http://backend:8080/actuator/prometheus

# Logs
docker logs --tail 100 todo-backend
docker logs --tail 100 todo-prometheus
docker logs --tail 100 todo-alertmanager
docker logs --tail 100 todo-cadvisor

# Current Docker restart/running-state metrics
./update-container-metrics.sh
cat node-exporter-textfile/todo_containers.prom
```

## 10. Operational checklist

- [ ] Application, Prometheus, Grafana, Alertmanager, Node Exporter and cAdvisor containers are running.
- [ ] Prometheus targets `prometheus`, `todo-backend`, `node-exporter`, and `cadvisor` are `up`.
- [ ] All five permanent Prometheus alert rules are loaded.
- [ ] Prometheus reports one active Alertmanager.
- [ ] Slack firing/resolved notification delivery remains valid.
- [ ] The Grafana dashboard has the 11 expected panels described above.
- [ ] The one-minute metrics script schedule is active and the textfile timestamp updates.
- [ ] EC2 memory, swap, disk and container resource usage are within acceptable limits.
- [ ] No secrets or generated metric files are committed.

## 11. Known limitations

- `todo_container_restart_count` is Docker's counter for the current container instance; a recreated container starts a new count. Retain deployment/restart logs for longer-term incident history.
- Average latency is implemented; p95/p99 latency needs verified histogram bucket metrics.
- Dedicated per-container CPU/memory panels and direct RDS/CloudWatch integration can be added later.
- The EC2 lab host has limited RAM. cAdvisor and the existing Java/Grafana stack require resource monitoring; consider a larger instance for sustained production traffic.

## 12. Summary

This implementation combines application, host and container metrics with 11 Grafana panels, five sustained-condition alerts, deployment health checks, and tested Slack notifications. It is designed to detect availability and resource problems early while avoiding alerts for brief, expected fluctuations.
