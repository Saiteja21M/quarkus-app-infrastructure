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
    subnets          = [data.aws_subnet.app_subnet_a.id, data.aws_subnet.app_subnet_b.id, data.aws_subnet.app_subnet_c.id]
    security_groups  = [data.aws_security_group.app_sg.id]
    assign_public_ip = true
  }
}

# Application Load Balancer
resource "aws_lb" "be_alb" {
  name               = "be-app-service"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.app_sg.id]
  subnets            = [data.aws_subnet.app_subnet_a.id, data.aws_subnet.app_subnet_b.id, data.aws_subnet.app_subnet_c.id]
}

# Target group for BE service
resource "aws_lb_target_group" "be_tg" {
  name        = "be-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.app_vpc.id
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

resource "aws_route53_record" "be_alb_record" {
  zone_id = data.aws_route53_zone.app_zone.zone_id
  name    = "backend-app"
  type    = "A"
  alias {
    name                   = aws_lb.be_alb.dns_name
    zone_id                = aws_lb.be_alb.zone_id
    evaluate_target_health = true
  }
}


# BE Quarkus App configuration end

data "aws_route53_zone" "app_zone" {
  name = "cloud-sai.com"
}

# Data sources for existing infrastructure
data "aws_vpc" "app_vpc" {
  filter {
    name   = "tag:Name"
    values = ["app-vpc"]
  }
}

data "aws_subnet" "app_subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["app-subnet-a"]
  }
}

data "aws_subnet" "app_subnet_b" {
  filter {
    name   = "tag:Name"
    values = ["app-subnet-b"]
  }
}

data "aws_subnet" "app_subnet_c" {
  filter {
    name   = "tag:Name"
    values = ["app-subnet-c"]
  }
}

data "aws_security_group" "app_sg" {
  filter {
    name   = "tag:Name"
    values = ["app-sg"]
  }
  vpc_id = data.aws_vpc.app_vpc.id
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

data "aws_ecs_cluster" "app_cluster" {
  cluster_name = "app-cluster"
}

output "be_ecr_repository_url" {
  value = data.aws_ecr_repository.be_app.repository_url
}

output "be_dns_name" {
  value = aws_lb.be_alb.dns_name
}