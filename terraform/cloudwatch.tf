# ./terraform/cloudwatch.tf

#---------------------------
# CloudWatch
#---------------------------
# Lambda関数のロググループ
resource "aws_cloudwatch_log_group" "lambda_log" {
  name = "/aws/lambda/python-lambda" #=> Lambda関数名と一致させる
  retention_in_days = 7
}

/*
Lambda関数のリソースブロック側では、追加の関連付けコードは不要：
Lambdaは、関数名に対応するCloudWatch Logsのロググループを自動的に認識し、ログを書き込みます。
つまり、CloudWatch Logsのロググループ名が/aws/lambda/{Lambda関数名}であれば、自動的に関連付けが行われます。このため、Lambda関数側で特別な設定をする必要はありません。
*/