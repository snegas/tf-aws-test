terraform {

  backend "s3" {
    bucket         = "test-tf-task-1"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"    
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
  
  required_version = ">= 0.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.16.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_secretsmanager_secret_version" "sec_rds_v" {
	secret_id = aws_secretsmanager_secret.secret_rds.id 
}

########################################################################
# VPC, SG resources 
########################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"  
  version = "2.64.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             	= data.aws_availability_zones.available.names
  
  database_subnets 	= var.db_subnet_cidr_blocks
  private_subnets 	= var.private_subnet_cidr_blocks
  public_subnets  	= var.public_subnet_cidr_blocks

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  create_database_subnet_group = true
  tags = var.vpc_tags
}

module "db_computed_source_sg" {
  source = "terraform-aws-modules/security-group/aws"
  vpc_id = local.vpc_id

  name = "db-restricted-sg-${var.project_name}"

  computed_ingress_with_cidr_blocks = [
    {
      rule        = "mysql-tcp"
      cidr_blocks = local.db_cidr_block
    }
  ]
  number_of_computed_ingress_with_cidr_blocks = 1
  
}

module "ecs_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.17.0"

  name        = "ecs-sg-${var.project_name}"
  description = "Security group for ECS task within VPC"
  vpc_id      = local.vpc_id

  computed_egress_with_source_security_group_id = [
    {
      rule        = "mysql-tcp"
      source_security_group_id = module.db_computed_source_sg.this_security_group_id
    }
  ]
  number_of_computed_egress_with_source_security_group_id = 1

  depends_on = [
    module.vpc,
    module.db_computed_source_sg,
  ]
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17"

  name = "load-balancer-sg-${var.project_name}"

  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = local.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  auto_ingress_rules = ["http-80-tcp"]
  
  depends_on = [
	module.vpc,
  ]
}

########################################################################
# ALB resources 
########################################################################
resource "aws_s3_bucket" logbucket {
  bucket = "test-alb-logs-2021-02"  
  versioning {
    enabled = true
  }  
  acl                            = "log-delivery-write"
  force_destroy                  = true
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 5.0"

  name = "test-alb"

  load_balancer_type = "application"

  vpc_id             = local.vpc_id
  security_groups    = [module.vpc.default_security_group_id, module.lb_security_group.this_security_group_id]
  subnets            = local.alb_subnets
  
 # access_logs = {
 #   bucket = "test-alb-logs-2021-02"
 # }

  target_groups = [
    {
      name_prefix      = "alb"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "Test"
  }
  
  depends_on = [
    module.vpc,
    aws_s3_bucket.logbucket,
  ]
}

resource "random_string" "lb_id" {
  length  = 4
  special = false
}

########################################################################
# ECS resources 
########################################################################
data "template_file" "task" {
  template = file("service.json")

  vars = {
 	uname = join(":",[local.secret1,"uname","",""])
	upass = join(":",[local.secret1,"upass","",""])
	ping_int = var.ping_interval
	dbhost = aws_db_instance.database.address
	connstr = "-u /$/{MYSQLUSER/} -p/$/{MYSQLUSERPASSWORD/} -h /$/{MYSQL_HOSTNAME/}"
  }
}


resource "aws_ecs_cluster" "ecs-cluster" {
  name = "test-cluster"
  depends_on = [
    module.vpc,
  ]
}

resource "aws_ecs_task_definition" "test_task" {
  family                   = "test-task-def"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "1024"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = data.template_file.task.rendered

}

module "ecs-fargate-scheduled-task" {
  source  = "cn-terraform/ecs-fargate-scheduled-task/aws"
  version = "1.0.13"
  
  ecs_cluster_arn = aws_ecs_cluster.ecs-cluster.arn
  ecs_execution_task_role_arn =aws_iam_role.ecs_task_execution_role.arn
  
  event_rule_description = "Test RDS availability periodically"
  event_rule_name = "ecs-rds-check"
  event_rule_schedule_expression = "cron(0 * * * ? *)" 
  event_target_ecs_target_security_groups = [module.ecs_security_group.this_security_group_id]
  event_target_ecs_target_subnets = slice(local.app_subnets,0,1)
  event_target_ecs_target_task_definition_arn = aws_ecs_task_definition.test_task.arn
  
  name_prefix = "sched"
}

########################################################################
# RDS resources 
########################################################################


resource "aws_db_subnet_group" "private" {
  subnet_ids = module.vpc.database_subnets
}

resource "aws_db_instance" "database" {
  allocated_storage = 5
  engine            = "mysql"
  engine_version	= "5.7"
  instance_class    = "db.t2.small"
  username          = local.db_creds.uname
  password          = local.db_creds.upass

  db_subnet_group_name = aws_db_subnet_group.private.name
  skip_final_snapshot = true

  storage_encrypted	= true
  
  depends_on = [
    aws_secretsmanager_secret_version.secret_rds_ver,
    module.db_computed_source_sg
  ]
}

########################################################################
# Locals
########################################################################

locals {
  alb_subnets		= slice(module.vpc.private_subnets,3,6)
  app_subnets 		= slice(module.vpc.private_subnets,0,3)
  alb_sn_cidr		= slice(module.vpc.private_subnets_cidr_blocks,3,6)
  app_sn_cidr		= slice(module.vpc.private_subnets_cidr_blocks,0,3)
  db_cidr_block		= join(",",[module.vpc.database_subnets_cidr_blocks[0],module.vpc.database_subnets_cidr_blocks[1],module.vpc.database_subnets_cidr_blocks[2]])

  db_creds 			= jsondecode(
    data.aws_secretsmanager_secret_version.sec_rds_v.secret_string
  )

  db_map 			=  {
						uname = var.lidb
						upass = var.pwdb
						}

  secret1 = data.aws_secretsmanager_secret_version.sec_rds_v.arn

  vpc_id 			= module.vpc.vpc_id
}
