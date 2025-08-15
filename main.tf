terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "sa-east-1"
}

# 1) IAM Role com trust apenas para o serviço AWS Lambda
resource "aws_iam_role" "role-iam-teste-2" {
  name = "role-iam-teste-2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "LambdaTrustPolicy",
        Effect    = "Allow",
        Principal = { Service = "lambda.amazonaws.com" },
        Action    = ["sts:AssumeRole", "sts:TagSession"],
        Condition = {
          "ArnLikeIfExists" = {
            "aws:SourceArn" = "arn:aws:*:*:*:*:*lambda-iam-teste*"
          }
        }
      }
    ]
  })
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
        Action   = ["lambda:*", "logs:*"],
        Resource = "*"
      }
    ]
  })
}


data "archive_file" "layer_zip" {
  type        = "zip"
  output_path = "${path.module}/dummy-layer.zip"

  source {
    content  = "This is a dummy layer file."
    filename = "dummy.txt"
  }
}

resource "aws_lambda_layer_version" "dummy_layer" {
  layer_name          = "dummy-layer"
  filename            = data.archive_file.layer_zip.output_path
  source_code_hash    = data.archive_file.layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
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

# Função Lambda usando a role acima
resource "aws_lambda_function" "lambda_iam_teste" {
  function_name = "lambda-iam-teste"
  role          = aws_iam_role.role-iam-teste-2.arn
  runtime       = "python3.12"
  handler       = "index.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  architectures = ["x86_64"]
  timeout       = 3

  layers = [aws_lambda_layer_version.dummy_layer.arn]
}

output "lambda_name" {
  value = aws_lambda_function.lambda_iam_teste.function_name
}

output "role_name" {
  value = aws_iam_role.role-iam-teste-2.arn
}
