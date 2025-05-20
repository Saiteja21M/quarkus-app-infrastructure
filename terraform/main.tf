terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "5.81.0"
        }
    }
}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "key_name" {default = "admin-key-pair"}

provider "aws" {
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    region = "eu-central-1"
}

module "cluster" {
    source = "./module"
    size = "t2.micro"
}

resource "aws_db_instance" "aws-db" {
    instance_class = "db.t3.micro"
    allocated_storage = 20
    engine = "postgres"
    engine_version = "13"
    identifier = "aws-db-instance"
    username = "quarkus"
    password = "quarkuspassword"
    db_name = "quarkusdb"
    parameter_group_name = "default.postgres13"
    skip_final_snapshot = true
}

resource "aws_instance" "EC2-server" {
    ami = "ami-0d8d11821a1c1678b"
    instance_type = module.cluster.ec2-size
    key_name = var.key_name
    tags = {
        Name = "EC2-Server"
    }
}

resource "aws_ecr_repository" "name" {
    name = "quarkus-app"
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration {
        scan_on_push = true
    }
    lifecycle {
        prevent_destroy = false
    }
    tags = {
        Name = "ECR-Repository"
    }
}

resource "aws_ecs_cluster" "aws-ecs-cluster" {
    name = "app-cluster"
    tags = {
        Name = "ECS-Cluster"
    }
}

resource "aws_ecs_task_definition" "ecs-task" {
    family                   = "ecs-task"
    container_definitions    = jsonencode([
        {
            name  = "app-container"
            image = aws_ecr_repository.name.repository_url
            memory = 512
            cpu    = 256
            essential = true
            portMappings = [
                {
                    containerPort = 80
                    hostPort      = 80
                }
            ]
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    "awslogs-group"         = "/ecs/app-cluster"
                    "awslogs-region"       = "eu-central-1"
                    "awslogs-stream-prefix" = "ecs"
                }
            }
        }
    ])
    depends_on = [aws_ecr_repository.name]
}

resource "aws_ecs_service" "ecs-service" {
    name            = "app-service"
    cluster         = aws_ecs_cluster.aws-ecs-cluster.id
    task_definition = aws_ecs_task_definition.ecs-task.arn
    desired_count   = 1
    launch_type     = "EC2"

    load_balancer {
        target_group_arn = aws_lb_target_group.aws_lb_target_group.arn
        container_name   = "app-container"
        container_port   = 80
    }

    depends_on = [aws_lb_listener.aws_lb_listener]
}

resource "aws_lb" "aws_lb" {
    name               = "aws-lb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.lb_sg.id]
    subnets            = aws_subnet.aws_subnet.*.id
}

resource "aws_lb_target_group" "aws_lb_target_group" {
    name     = "aws-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.aws_vpc.id
}

resource "aws_lb_listener" "aws_lb_listener" {
    load_balancer_arn = aws_lb.aws_lb.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.aws_lb_target_group.arn
    }
}

resource "aws_security_group" "lb_sg" {
    name        = "lb-sg"
    description = "Allow HTTP traffic"
    vpc_id      = aws_vpc.aws_vpc.id

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_vpc" "aws_vpc" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.aws_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.aws_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.aws_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_subnet" "aws_subnet" {
    count                   = 2
    vpc_id                  = aws_vpc.aws_vpc.id
    cidr_block              = "10.0.${count.index}.0/24"
    availability_zone       = data.aws_availability_zones.available.names[count.index]
}

data "aws_availability_zones" "available" {}

resource "aws_eip" "eip" {
    instance = aws_instance.EC2-server.id
}

data "aws_secretsmanager_secret" "secret" {
    name = "aws-secret-key"
}

data "aws_secretsmanager_secret_version" "secret_version" {
    secret_id = data.aws_secretsmanager_secret.secret.id
}

locals {
    aws_secret_key = jsondecode(data.aws_secretsmanager_secret_version.secret_version.secret_string)["access-secret-key"]
}

output "cluster_size" {
    value = module.cluster.ec2-size
}

output "secret-details" {
    value = local.aws_secret_key
    sensitive = true
}

output "ecr_repository_url" {
    value = aws_ecr_repository.name.repository_url
}