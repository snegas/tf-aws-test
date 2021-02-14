resource "aws_secretsmanager_secret" "secret_rds" {
  name = "/rds/creds"
  description = "RDS creds secret"
  secret_key_value = {
    user = "${var.uname}"
    pass = "${var.upass}"
  }
}

variable "db_creds" {
  default = {
    uname = "value1"
    upass = "value2"
  }

  type = map(string)
}

resource "aws_secretsmanager_secret_version" "secret_rds_ver" {
  secret_id     = aws_secretsmanager_secret.secret_rds.id
  secret_string = jsonencode(var.db_creds)
}


output "example" {
  value = jsondecode(aws_secretsmanager_secret_version.example.secret_string)["key1"]
}
