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

//FE Angular App configuration start
# ECS Task Definition for Angular App (Fargate)
resource "aws_ecs_task_definition" "fe_app_task_def" {
  family                   = "angular-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "angular-app-container"
      image     = data.aws_ecr_repository.fe_app.repository_url
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
      environment = [
        {
          name  = "BE_HOST"
          value = data.aws_lb.be_alb.dns_name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "angular"
        }
      }
    }
  ])
  tags = {
    Name = "ECS-Task-Definition-Angular"
  }
}

# ECS Fargate Service for Angular Apps
resource "aws_ecs_service" "fe_app_service" {
  name            = "angular-app-service"
  cluster         = data.aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.fe_app_task_def.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.fe_app_tg.arn
    container_name   = "angular-app-container"
    container_port   = 5000
  }
  depends_on = [aws_lb_listener.fe_alb_listener]

  network_configuration {
    subnets          = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
    security_groups  = ["sg-009cc415372b1beee"]
    assign_public_ip = true
  }
}

# Application Load Balancer for FE app
resource "aws_lb" "fe_alb" {
  name               = "fe-app-service"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-009cc415372b1beee"]
  subnets            = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
}

# Target group for FE app
resource "aws_lb_target_group" "fe_app_tg" {
  name        = "fe-app-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = "vpc-079bb37d3813c4b6a"
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener for ALB (HTTP 80)
resource "aws_lb_listener" "fe_alb_listener" {
  load_balancer_arn = aws_lb.fe_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fe_app_tg.arn
  }
}

# Create Route 53 Hosted Zone
resource "aws_route53_zone" "fe_hosted_zone" {
  name = "cloud.sai.com"
}

# Create A record for FE app ALB
resource "aws_route53_record" "fe_app_record" {
  zone_id = aws_route53_zone.fe_hosted_zone.zone_id
  name    = "favourite-shows.cloud.sai.com"
  type    = "A"

  alias {
    name                   = aws_lb.fe_alb.dns_name
    zone_id                = aws_lb.fe_alb.zone_id
    evaluate_target_health = true
  }
}

# FE Angular App configuration end

data "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/fe-app"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_ecr_repository" "fe_app" {
  name = "angular-app"
}

data "aws_lb" "be_alb" {
  name = "be-app-service"
}

data "aws_ecs_cluster" "app_cluster" {
  cluster_name = "app-cluster"
}

output "fe_ecr_repository_url" {
  value = data.aws_ecr_repository.fe_app.repository_url
}

output "fe-app-host" {
  value = aws_lb.fe_alb.dns_name
}

output "be-app-host" {
  value = data.aws_lb.be_alb.dns_name
}