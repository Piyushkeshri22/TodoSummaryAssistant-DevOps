# AWS Setup and Infrastructure Notes

## Overview

This repository provisions the Todo Summary Assistant infrastructure using Terraform under `aws/iac/`. The application is deployed to an EC2 instance and uses an Amazon RDS MySQL database in private subnets. Docker Compose runs the frontend, backend, and monitoring containers on the EC2 host.

The values below describe the checked-in Terraform design. Resource IDs, endpoint hostnames, public IP addresses, SSH source IPs, and credentials are environment-specific and should not be hardcoded in documentation.

## Network design

- **Region:** `ap-south-1` (Mumbai), controlled by the `aws_region` Terraform variable.
- **VPC:** `10.20.0.0/16`, controlled by `vpc_cidr`.
- **Public subnets:** `10.20.1.0/24` and `10.20.2.0/24`, spread across available Availability Zones. The public route table sends internet-bound traffic to an Internet Gateway.
- **Private database subnets:** `10.20.11.0/24` and `10.20.12.0/24`, registered in the RDS DB subnet group. They do not receive a direct Internet Gateway route.
- **Application host:** EC2 is placed in the first public subnet and receives a public IPv4 address.
- **Database:** RDS is configured with `publicly_accessible = false` and is attached to the private DB subnet group.

The private route table currently has no NAT Gateway route. This is sufficient for a private RDS database, which does not need a direct inbound connection from the public internet. If private instances later need outbound software downloads or AWS API access, design NAT or VPC endpoints explicitly and account for their cost.

## Compute and database

### EC2

Terraform selects an Amazon Linux 2023 x86-64 AMI and defaults to instance type `t3.micro`. Its encrypted `gp3` root EBS volume is 8 GiB and is configured for deletion with the instance. EC2 user data installs Docker and the Docker Compose CLI plugin and enables Docker at boot. IMDSv2 is required (`http_tokens = "required"`).

The instance uses an IAM instance profile. The role currently has the AWS-managed `AmazonSSMManagedInstanceCore` policy attached. The current Jenkins deployment flow uses SSH; the existence of the SSM policy does not mean the pipeline has been migrated to SSM.

### Amazon RDS for MySQL

Terraform creates a MySQL RDS instance with defaults of class `db.t3.micro`, database name `todo_db`, and 20 GiB allocated storage. Storage encryption is enabled, public accessibility is disabled, and inbound MySQL access is allowed only from the application EC2 security group on TCP 3306.

The checked-in configuration currently sets one day of automated backup retention, `multi_az = false`, deletion protection off, and `skip_final_snapshot = true`. These are cost/demo choices, not recommended production recovery settings. Before relying on this deployment for important data, enable appropriate backup retention, consider Multi-AZ, enable deletion protection, and retain a final snapshot when deleting the database.

## Security groups and access

| Resource | Inbound rule in Terraform | Purpose |
|---|---|---|
| EC2 | TCP 22 from `ssh_allowed_cidr` | Restricted SSH administration from the operator's current public IP (`/32`) |
| EC2 | TCP 3000 from `0.0.0.0/0` | Public React/Nginx frontend |
| EC2 | TCP 3001 from `ssh_allowed_cidr` | A Terraform rule for Grafana; current Compose binds Grafana to `127.0.0.1:3001`, so access should use the SSH tunnel below. This ingress can be removed from Terraform for a tighter rule set. |
| RDS | TCP 3306 from the EC2 security group only | Backend database connectivity; no public database access |

Security-group egress is currently allowed to `0.0.0.0/0`. Keep SSH source ranges narrow and update `ssh_allowed_cidr` when the operator's public IP changes. Do not open MySQL to `0.0.0.0/0`.

The EC2 host serves the frontend on port 3000. Prometheus is bound to `127.0.0.1:9090`, Grafana to `127.0.0.1:3001`, and Alertmanager has no published host port in the live Compose configuration. Use a local SSH tunnel for administrative access:

```powershell
ssh -i "$env:USERPROFILE\.ssh\todo-summary-jenkins" -N -L 3001:127.0.0.1:3001 -L 9090:127.0.0.1:9090 ec2-user@<EC2_PUBLIC_IP>
```

Then open Grafana at `http://localhost:3001` and Prometheus at `http://localhost:9090`. Replace the placeholder with the instance's current public IP; do not put a changing IP in source-controlled configuration.

## Secrets and Terraform state

- Supply `db_password` through a local, ignored `terraform.tfvars` file or a proper secret-management workflow. Do not commit real `.tfvars` files.
- The application receives database credentials through a server-side environment file, rather than a committed source file. Protect it with restrictive permissions (for example `chmod 600 .env`).
- The Slack Incoming Webhook is a secret. Keep the webhook-bearing `alertmanager.yml` on the EC2 host with restricted permissions; never commit it or put it in screenshots, logs, or README examples.
- Keep Terraform state and `.terraform/` private. State files can contain sensitive resource attributes even when an input variable is marked sensitive.
- The `.gitignore` under `aws/iac/` should continue to exclude state files, local variable files, and generated Terraform content.

## Reprovisioning and cost control

From `aws/iac/`, use the intended Terraform workflow:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Review the plan before applying it. Keep `terraform.tfvars` local and supply the SSH-allowed CIDR and database password securely. After deployment, use the Terraform outputs for the current EC2 IP, application URL, and RDS endpoint; these values can change when resources are recreated.

When you intentionally finish testing and no longer need the resources, review the consequences, back up any required data, and run `terraform destroy` from the same state directory. The present RDS configuration skips a final snapshot, so destruction can permanently delete database contents. Confirm all costs and resources are removed in the AWS console after destroying the lab.

## Architecture diagram

See [`architecture-diagram.png`](architecture-diagram.png) for a high-level view of the CI/CD flow, AWS network boundary, application services, database, and monitoring/alerting path.
