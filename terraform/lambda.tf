# ./terraform/lambda.tf

#--------------------
# 変数
#--------------------
# 他リソースで使用する変数を定義
locals {
  s3_bucket      = aws_s3_bucket.lambda_artifacts.bucket #=> S3バケット名
  s3_key_prefix  = "lambda-python"
  s3_base_path   = "${local.s3_bucket}/${local.s3_key_prefix}"
  python_codedir = "${path.module}/../src"
  hash_file_name = "image_digest.txt"
}

#--------------------
# Lambda
#--------------------
# Lambda関数の作成
resource "aws_lambda_function" "python_lambda" {
  function_name    = "python-lambda"
  package_type     = "Image"
  image_uri        = "${aws_ecr_repository.python_lambda.repository_url}:latest"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = base64sha256(data.aws_s3_object.image_hash.body)

  # 環境変数にバケット名を設定
  environment {
    variables = {
      S3_BUCKET_NAME = local.s3_bucket
    }
  } 
}

# S3からDockerイメージのハッシュを取得するデータソース
data "aws_s3_object" "image_hash" { 
  depends_on = [null_resource.lambda_build] # イメージビルドが完了したら実行 
  bucket = local.s3_bucket
  key    = "${local.s3_key_prefix}/${local.hash_file_name}"
}


#--------------------
# null_resource
#--------------------
# Dockerイメージのビルド・プッシュ処理の定義
resource "null_resource" "lambda_build" {
  depends_on = [aws_ecr_repository.python_lambda]

  # トリガーとしてコードの更新をチェック
  triggers = {
    code_diff = sha256(join("", [
      for file in fileset(local.python_codedir, "*")  # コードディレクトリ内のファイルをチェック
      : filesha256("${local.python_codedir}/${file}")
    ]))
  }

  # 1. Dockerイメージのビルド
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && docker build . -f docker/Dockerfile --platform linux/amd64 -t ${aws_ecr_repository.python_lambda.repository_url}:latest"
  }

  # 2. DockerイメージをECRにプッシュ
  provisioner "local-exec" {
    command = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.python_lambda.repository_url} && docker push ${aws_ecr_repository.python_lambda.repository_url}:latest"
  }

  # 3. Dockerイメージのハッシュを生成し、ファイルに保存
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && docker inspect --format='{{index .RepoDigests 0}}' ${aws_ecr_repository.python_lambda.repository_url}:latest > ${local.hash_file_name}"
  }

  # 4. ハッシュファイルをS3にアップロードし、Lambda関数の更新に使用
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && aws s3 cp ${local.hash_file_name} s3://${local.s3_base_path}/${local.hash_file_name} --content-type \"text/plain\""
  }
}