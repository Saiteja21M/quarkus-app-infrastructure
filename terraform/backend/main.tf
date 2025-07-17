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

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = "eu-central-1"
}

# --- New VPC and networking resources ---
resource "aws_vpc" "be_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "quarkus-app-vpc"
  }
}

resource "aws_internet_gateway" "be_igw" {
  vpc_id = aws_vpc.be_vpc.id
  tags = {
    Name = "quarkus-app-igw"
  }
}

resource "aws_subnet" "be_subnet_a" {
  vpc_id                  = aws_vpc.be_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "quarkus-app-subnet-a"
  }
}

resource "aws_subnet" "be_subnet_b" {
  vpc_id                  = aws_vpc.be_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "quarkus-app-subnet-b"
  }
}

resource "aws_subnet" "be_subnet_c" {
  vpc_id                  = aws_vpc.be_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "eu-central-1c"
  map_public_ip_on_launch = true
  tags = {
    Name = "quarkus-app-subnet-c"
  }
}

resource "aws_route_table" "be_rt" {
  vpc_id = aws_vpc.be_vpc.id
  tags = {
    Name = "quarkus-app-rt"
  }
}

resource "aws_route" "be_route" {
  route_table_id         = aws_route_table.be_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.be_igw.id
}

resource "aws_route_table_association" "be_rta_a" {
  subnet_id      = aws_subnet.be_subnet_a.id
  route_table_id = aws_route_table.be_rt.id
}

resource "aws_route_table_association" "be_rta_b" {
  subnet_id      = aws_subnet.be_subnet_b.id
  route_table_id = aws_route_table.be_rt.id
}

resource "aws_route_table_association" "be_rta_c" {
  subnet_id      = aws_subnet.be_subnet_c.id
  route_table_id = aws_route_table.be_rt.id
}

# --- Security group allowing traffic from all to port 8080 ---
resource "aws_security_group" "be_sg" {
  name        = "quarkus-app-sg"
  description = "Allow all inbound traffic to port 8080"
  vpc_id      = aws_vpc.be_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "quarkus-app-sg"
  }
}

# BE Quarkus App configuration start
# ECS Task Definition for Quarkus App (Fargate)
resource "aws_ecs_task_definition" "be_app_task_def" {
  family                   = "quarkus-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "quarkus-app-container"
      image     = data.aws_ecr_repository.be_app.repository_url
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      environment = [
        {
          name  = "BE_HOST"
          value = "data.aws_lb.be_alb.dns_name"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "quarkus"
        }
      }
    }
  ])
  tags = {
    Name = "ECS-Task-Definition"
  }
}

# ECS Fargate Service
resource "aws_ecs_service" "be_app_service" {
  name            = "quarkus-app-service"
  cluster         = data.aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.be_app_task_def.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.be_tg.arn
    container_name   = "quarkus-app-container"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.be_listener]

  network_configuration {
    subnets          = [aws_subnet.be_subnet_a.id, aws_subnet.be_subnet_b.id, aws_subnet.be_subnet_c.id]
    security_groups  = [aws_security_group.be_sg.id]
    assign_public_ip = true
  }
}

# Application Load Balancer
resource "aws_lb" "be_alb" {
  name               = "be-app-service"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.be_sg.id]
  subnets            = [aws_subnet.be_subnet_a.id, aws_subnet.be_subnet_b.id, aws_subnet.be_subnet_c.id]
}

# Target group for BE service
resource "aws_lb_target_group" "be_tg" {
  name        = "be-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.be_vpc.id
  target_type = "ip"
  health_check {
    path                = "/home"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener for ALB
resource "aws_lb_listener" "be_listener" {
  load_balancer_arn = aws_lb.be_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.be_tg.arn
  }
}

# BE Quarkus App configuration end

data "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/quarkus-app"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_ecr_repository" "be_app" {
  name = "quarkus-app"
}

data "aws_ecs_cluster" "app_cluster" {
  cluster_name = "app-cluster"
}

output "be_ecr_repository_url" {
  value = data.aws_ecr_repository.be_app.repository_url
}

output "be_dns_name" {
  value = aws_lb.be_alb.dns_name
}