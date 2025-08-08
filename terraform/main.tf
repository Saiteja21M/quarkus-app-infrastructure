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

# --- New VPC and networking resources ---
resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "app-vpc"
  }
}

resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = "app-igw"
  }
}

resource "aws_subnet" "app_subnet_a" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "app-subnet-a"
  }
}

resource "aws_subnet" "app_subnet_b" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "app-subnet-b"
  }
}

resource "aws_subnet" "app_subnet_c" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "eu-central-1c"
  map_public_ip_on_launch = true
  tags = {
    Name = "app-subnet-c"
  }
}

resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = "app-rt"
  }
}

resource "aws_route" "app_route" {
  route_table_id         = aws_route_table.app_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_igw.id
}

resource "aws_route_table_association" "app_rta_a" {
  subnet_id      = aws_subnet.app_subnet_a.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table_association" "app_rta_b" {
  subnet_id      = aws_subnet.app_subnet_b.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table_association" "app_rta_c" {
  subnet_id      = aws_subnet.app_subnet_c.id
  route_table_id = aws_route_table.app_rt.id
}

# --- Security group allowing traffic from all to port 8080 ---
resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow all inbound traffic to port 8080"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4200
    to_port     = 4200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "app-sg"
  }
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

output "be_ecr_repository_url" {
  value = data.aws_ecr_repository.be_app.repository_url
}

output "fe_ecr_repository_url" {
  value = data.aws_ecr_repository.fe_app.repository_url
}