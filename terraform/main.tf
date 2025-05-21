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
resource "aws_ecr_repository" "name" {
  name                 = "quarkus-app"
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

resource "aws_ecs_cluster" "main" {
  name = "quarkus-app-cluster"
  tags = {
    Name = "ECS-Cluster"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = data.aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for Fargate
resource "aws_ecs_task_definition" "main" {
  family                   = "quarkus-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "4096"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "quarkus-app-container"
      image     = aws_ecr_repository.name.repository_url
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
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
resource "aws_ecs_service" "main" {
  name            = "quarkus-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
    security_groups  = ["sg-009cc415372b1beee"]
    assign_public_ip = true
  }
}

data "aws_secretsmanager_secret" "secret" {
  name = "aws-secret-key"
}

data "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/quarkus-app"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_secretsmanager_secret_version" "secret_version" {
  secret_id = data.aws_secretsmanager_secret.secret.id
}

locals {
  aws_secret_key = jsondecode(data.aws_secretsmanager_secret_version.secret_version.secret_string)["access-secret-key"]
}

output "ecr_repository_url" {
  value = aws_ecr_repository.name.repository_url
}