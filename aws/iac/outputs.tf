output "rds_endpoint" {
  description = "Private RDS endpoint"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.mysql.port
}

output "rds_database_name" {
  description = "Application database name"
  value       = aws_db_instance.mysql.db_name
}