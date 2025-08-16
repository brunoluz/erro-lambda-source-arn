terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "sa-east-1"
}

data "aws_availability_zones" "azs" {
  state = "available"
}


resource "aws_vpc" "lambda_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-lambda-teste" }
}



# Inline policy permitindo todas as ações de Lambda e EC2
resource "aws_iam_role_policy" "inline-lambda-policy" {
  name = "inline-lambda-policy"
  role = aws_iam_role.role-iam-teste-2.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowServices",
        Effect   = "Allow",
        Action   = ["lambda:*", "logs:*", "ec2:*"],
        Resource = "*"
      }
    ]
  })
}



# 2) Código da Lambda (Python) empacotado via data.archive_file
# Handler: index.lambda_handler
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-iam-teste.zip"

  source {
    content  = <<-PY
      def lambda_handler(event, context):
          print("hello world")
          return {"message": "hello world"}
    PY
    filename = "index.py"
  }
}

################### AQUI ###################################

# Subnets sem sobreposição
resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.lambda_vpc.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "subnet-a" }
}

# resource "aws_subnet" "subnet_b" {
#   vpc_id                  = aws_vpc.lambda_vpc.id
#   cidr_block              = "10.10.2.0/24"
#   availability_zone       = data.aws_availability_zones.azs.names[1]
#   map_public_ip_on_launch = false
#   tags = { Name = "subnet-b" }
# }


# Security Group para a Lambda (sem ingress; egress liberado)
resource "aws_security_group" "lambda_sg" {
  name        = "securitygroupteste"
  description = "SG da Lambda - sem ingress; egress liberado"
  vpc_id      = aws_vpc.lambda_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-lambda-teste" }
}

# resource "aws_lambda_function" "lambda_aaaaa" {
#   function_name = "lambda_aaaaa"
#   role          = aws_iam_role.role-iam-teste-2.arn
#   runtime       = "python3.12"
#   handler       = "index.lambda_handler"

#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256

#   architectures = ["x86_64"]
#   timeout       = 3
# }

resource "null_resource" "always_run" {
  triggers = {
    timestamp = "${timestamp()}"
  }
}


resource "aws_lambda_function" "lambda_iam_teste" {
  function_name = "lambda-iam-teste"
  role          = aws_iam_role.role-iam-teste-2.arn
  runtime       = "python3.12"
  handler       = "index.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  architectures = ["x86_64"]
  timeout       = 3

  vpc_config {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = [aws_subnet.subnet_a.id]
  }

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}


# 1) IAM Role com trust apenas para o serviço AWS Lambda
resource "aws_iam_role" "role-iam-teste-2" {
  name = "role-iam-teste-2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "LambdaTrustPolicy",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "sts:AssumeRole",
        "sts:TagSession"],
        Condition = {
          "ArnLike" = {
            "aws:SourceArn" = "arn:aws:lambda:sa-east-1:960669553273:function:lambda-iam-teste"
          }
        }
      },

      {
        Sid    = "EC2NetworkInterfaceTrustPolicy",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ],
        Condition = {
          "ArnEqualsIfExists" = {
            "lambda:SourceFunctionArn" : "arn:aws:lambda:sa-east-1:960669553273:function:lambda-iam-teste"
          }
        }
      },
    ]
  })
}