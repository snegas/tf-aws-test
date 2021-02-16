output vpc_arn {
  description = "ARN of the vpc"
  value       = module.vpc.vpc_arn
}

output sec_v_arn {
  description = "Secrets version arn"
  value 	  = aws_secretsmanager_secret_version.secret_rds_ver.arn
}

output sec_arn {
  description = "Secrets arn"
  value 	  = aws_secretsmanager_secret.secret_rds.arn
}
