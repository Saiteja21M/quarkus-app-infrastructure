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

resource "aws_ecs_cluster" "app_cluster" {
  name = "app-cluster"
  tags = {
    Name = "ECS-Cluster"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = data.aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
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
  cluster         = aws_ecs_cluster.app_cluster.id
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
    subnets          = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
    security_groups  = ["sg-009cc415372b1beee"]
    assign_public_ip = true
  }
}

# Application Load Balancer
resource "aws_lb" "be_alb" {
  name               = "be-app-service"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-009cc415372b1beee"]
  subnets            = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
}

# Target group for BE service
resource "aws_lb_target_group" "be_tg" {
  name        = "be-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = "vpc-079bb37d3813c4b6a"
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

output "be_ecr_repository_url" {
  value = data.aws_ecr_repository.be_app.repository_url
}

output "be_dns_name" {
  value = aws_lb.be_alb.dns_name
}