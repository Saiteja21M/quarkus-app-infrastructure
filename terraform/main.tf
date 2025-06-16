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
          containerPort = 80
          hostPort      = 80
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
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.fe_app_task_def.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
    security_groups  = ["sg-009cc415372b1beee"]
    assign_public_ip = true
  }
}
//FE Angular App configuration end

# BE Quarkus App configuration start
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

  network_configuration {
    subnets          = ["subnet-0cb003bdf4847a5da", "subnet-0df54116201e545d0", "subnet-02bc517d0f103bde0"]
    security_groups  = ["sg-009cc415372b1beee"]
    assign_public_ip = true
  }
}
# BE Quarkus App configuration end

data "aws_secretsmanager_secret" "secret" {
  name = "aws-secret-key"
}

data "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/quarkus-app"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_ecr_repository" "be_app" {
  name = "quarkus-app"
}

data "aws_ecr_repository" "fe_app" {
  name = "angular-app"
}

output "be-ecr_repository_url" {
  value = data.aws_ecr_repository.be_app.repository_url
}

output "fe_ecr_repository_url" {
  value = data.aws_ecr_repository.fe_app.repository_url
}