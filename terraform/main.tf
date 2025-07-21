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