# ./terraform/iam.tf

#--------------------
# IAM
#--------------------
# Lambda IAMロールを作成
resource "aws_iam_role" "lambda_role" {
  name = "role-for-lambda-python"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": { "Service": "lambda.amazonaws.com" },
        "Effect": "Allow"
      }
    ]
  })
}

## Cloudwatchログ用途ポリシー
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "lambda-cloudwatch-logs-policy"
  role = aws_iam_role.lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"          
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

## S3アクセス用途ポリシー
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-access-policy"
  role = aws_iam_role.lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.lambda_artifacts.arn}",         #=> バケット自体へのアクセス権
          "${aws_s3_bucket.lambda_artifacts.arn}/*"       #=> バケット内のオブジェクトへのアクセス権
        ]
      }
    ]
  })
}
