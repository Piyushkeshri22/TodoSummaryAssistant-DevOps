# Monitoring configuration

This folder contains the repository versions of the Prometheus scrape configuration and the five permanent alert rules used by Todo Summary Assistant.

- `prometheus.yml` scrapes Prometheus, the Spring Boot Actuator Prometheus endpoint, and Node Exporter. It routes alerts to Alertmanager at `alertmanager:9093` on the Compose network.
- `alert-rules.yml` defines backend availability, high CPU, low available memory, low root-disk space, and high JVM heap alerts.

When using these files in Docker Compose, mount them to the container paths referenced by the configuration:

```yaml
volumes:
  - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
  - ./monitoring/alert-rules.yml:/etc/prometheus/alert-rules.yml:ro
```

Keep the Alertmanager configuration containing the real Slack Incoming Webhook outside source control. Do not put webhook URLs, passwords, or API keys in this repository.
