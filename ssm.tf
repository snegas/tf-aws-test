resource "aws_secretsmanager_secret" "secret_rds" {
  name = "/rds/creds"
  description = "RDS creds secret"
}

variable "db_creds" {
  type = map(string)
}

resource "aws_secretsmanager_secret_version" "secret_rds_ver" {
  secret_id     = aws_secretsmanager_secret.secret_rds.id
  secret_string = jsonencode(var.db_creds)
}
