# ./terraform/ecr.tf

#--------------------
# ECR
#--------------------
locals {
  ecr_repository_name = "python-lambda-repo"
}

# Dockerイメージ格納用リポジトリを作成
resource "aws_ecr_repository" "python_lambda" {
  name = local.ecr_repository_name
  force_delete = true
}