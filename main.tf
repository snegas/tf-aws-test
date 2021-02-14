terraform {
  backend "s3" {
    bucket         = "test-tf"
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
  profile = test1
}

data "aws_availability_zones" "available" {
  state = "available"
  #filter by region?
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
  public_subnets  	= slice(var.public_subnet_cidr_blocks, 0, 2)

  enable_nat_gateway = true
  enable_vpn_gateway = false

 # allowed_ports                       = ["8080", "3306", "443", "80"]
  create_database_subnet_group = false
  tags = var.vpc_tags
}

module "db_computed_source_sg" {
  source = "terraform-aws-modules/security-group/aws"
  vpc_id = local.vpc_id

  name = db-restricted-sg-${var.project_name}
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = "${module.ecs_security_group.this_security_group_id}"
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1
}

module "ecs_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.17.0"

  name        = "ecs-sg-${var.project_name}"
  description = "Security group for ECS task within VPC"
  vpc_id      = local.vpc_id

  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  egress_with_cidr_blocks = [
    {
      rule        = "mysql-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17"

  name = "load-balancer-sg-${var.project_name}"

  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = "${local.vpc_id}"

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

########################################################################
# ALB resources 
########################################################################

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 5.0"

  name = "test-alb"

  load_balancer_type = "application"

  vpc_id             = local.vpc_id
  security_groups    = ["${module.vpc.security_group_id}", "${module.lb_security_group.this_security_group_id}"]
  subnets            = ["${module.vpc.vpc-privatesubnet-ids}"]
  
  access_logs = {
    bucket = "my-alb-logs"
  }

  target_groups = [
    {
      name_prefix      = "pref-"
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
}

resource "random_string" "lb_id" {
  length  = 4
  special = false
}


########################################################################
# ECS resources 
########################################################################

resource "aws_ecs_cluster" "ecs-cluster" {
  name = "test-cluster"
}

resource "aws_ecs_task_definition" "test_task" {
  family                   = "test-task-def"
  task_role_arn            = "${aws_iam_role.ecs_task_role}"
  execution_role_arn       = "${aws_iam_role.ecs_task_execution_role}"
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "1024"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("service.json")
}

########################################################################
# RDS resources 
########################################################################

#data "aws_secretsmanager_secret" "rdssec" {
#  name = "secret_rds"
#}

data "aws_secretsmanager_secret_version" "sec_rds_v" {
# secret_id = data.aws_secretsmanager_secret.rdssec.id 
  secret_id = "secret_rds_ver"
}

resource "aws_db_subnet_group" "private" {
  subnet_ids = module.vpc.database_subnets
}

resource "aws_db_instance" "database" {
  allocated_storage = 5
  engine            = "mysql"
  engine_version	= "5.7"
  instance_class    = "db.t2.micro"
  username          = local.db_creds.uname
  password          = local.db_creds.upass

  db_subnet_group_name = aws_db_subnet_group.private.name
  skip_final_snapshot = true

  storage_encrypted	= true
}

locals {
  db_creds 			= jsondecode(
    data.aws_secretsmanager_secret_version.sec_rds_v.secret_string
  )
  vpc_id 			= local.vpc_id
}
