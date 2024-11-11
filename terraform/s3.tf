# ./terraform/s3.tf

#--------------------
# S3
#--------------------
# アーティファクトを保存するためのS3バケットを作成：
## (ハッシュファイルとLambda関数が生成するデータファイル)
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "lambda-artifacts-${random_id.suffix.hex}" #=>ランダムな16進数の文字列を追加
  force_destroy = true
}

## S3バケット名にランダム文字列を付加
resource "random_id" "suffix" {
  byte_length = 4  #=>4バイトで8文字の16進数を生成
}

## S3バケットポリシーの追加
resource "aws_s3_bucket_policy" "lambda_bucket_policy" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          "AWS": aws_iam_role.lambda_role.arn
        },
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "${aws_s3_bucket.lambda_artifacts.arn}",
          "${aws_s3_bucket.lambda_artifacts.arn}/*"
        ]
      }
    ]
  })
}
