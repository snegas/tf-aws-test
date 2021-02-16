# Input variable definitions

variable aws_region {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
variable project_name {
  description = "Name of the project. Used in resource names and tags."
  type        = string
  default     = "test-app"
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
  default     = "test-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_tags" {
  description = "Tags to apply to resources created by VPC module"
  type        = map(string)
  default     = {
    Terraform   = "true"
    Environment = "dev"
  }
}

variable public_subnet_cidr_blocks {
  description = "Available cidr blocks for public subnets"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
  ]
}

variable private_subnet_cidr_blocks {
  description = "Available cidr blocks for private subnets"
  type        = list(string)
  default = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24",
    "10.0.104.0/24",
    "10.0.105.0/24",
    "10.0.106.0/24",
  ]
}

variable db_subnet_cidr_blocks {
  description = "Available cidr blocks for database subnets"
  type        = list(string)
  default = [
    "10.0.108.0/24",
    "10.0.109.0/24",
    "10.0.110.0/24",
  ]
}

variable instance_type {
  description = "Type of EC2 instance to use."
  type        = string
  default     = "t2.micro"
}

variable ping_interval {
  description = "Checking DB availability interval, "
  type        = number
  default     = 3600
}

variable lidb {	#db user name (login)
  type = string
  sensitive = true
}

variable pwdb { #db user pass
  type = string
  sensitive = true
}
