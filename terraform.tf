# FIXME introduce "depends_on"'s where required, to make things less fragile when doing incremental IaC development

terraform {
  backend "s3" {
    bucket = "aee97cb3ad288ef0add6c6b5b5fae48a" #FIXME not hard-coded
    key    = "hellocovid"
    region = "eu-central-1"
  }
}

provider "aws" {
  region  = "eu-central-1"
  version = "~> 2.0"
}

data "aws_region" "current" {}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnet_ids" "default" {
  vpc_id = aws_default_vpc.default.id
}

resource "aws_ecs_cluster" "this" {
  name               = terraform.workspace
  capacity_providers = ["FARGATE"]
}

resource "aws_iam_role" "task_execution_role" {
  name = "${terraform.workspace}_task_execution"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task_execution_role_de" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "this" {
  #FIXME sample task_role_arn (e.g. S3 permissions)
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  family                   = terraform.workspace
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  requires_compatibilities = ["FARGATE"]
  container_definitions    = <<EOF
[
  {
    "name": "${terraform.workspace}",
    "image": "nginx",
    "cpu": 512,
    "memory": 512,
    "essential": true,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ],
    "logConfiguration" : {
      "logDriver": "awslogs",
      "options": { 
          "awslogs-group" : "/ecs/${terraform.workspace}",
          "awslogs-region": "${data.aws_region.current.name}",
          "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
EOF
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${terraform.workspace}"
}

resource "aws_ecs_service" "this" {
  depends_on = [
    aws_lb.this
  ]

  name            = terraform.workspace
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = terraform.workspace
    container_port   = 80
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnet_ids.default.ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }
}

resource "aws_security_group" "service" {
  name        = "${terraform.workspace}_service"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancer.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "loadbalancer" {
  name        = "${terraform.workspace}_loadbalancer"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

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

resource "aws_lb" "this" {
  name               = terraform.workspace
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loadbalancer.id]
  subnets            = data.aws_subnet_ids.default.ids
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_target_group" "this" {
  name        = terraform.workspace
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"
}

output "loadbalancer_dns_name" {
  value = aws_lb.this.dns_name
}
