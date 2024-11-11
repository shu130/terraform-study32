# ./src/app.py

import os   #=> osモジュールをインポート
import json #=>標準ライブラリ
import boto3
import requests
from datetime import datetime #=>標準ライブラリ

# S3クライアントを初期化
s3_client = boto3.client("s3")

def lambda_handler(event, context):
    # 1. 外部APIからデータを取得(今回は、ダミーデータを返す無料のAPIを使用する)
    api_url = "https://jsonplaceholder.typicode.com/todos/1" #=> 外部APIのURL
    response = requests.get(api_url)

    # API呼び出しが成功したかチェック
    if response.status_code == 200:
        data = response.json()  # JSONデータを取得
    else:
        return {
            "statusCode": response.status_code,
            "body": json.dumps({"error": "Failed to fetch data from API"})
        }

    # 2. 取得したデータをS3に保存
    bucket_name = os.getenv("S3_BUCKET_NAME") #=>lamdba.tfのなかの環境変数を指定    
    file_name = f"data-{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.json"

    # データをJSONとして保存
    s3_client.put_object(
        Bucket=bucket_name,
        Key=file_name,
        Body=json.dumps(data),
        ContentType="application/json"
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Data successfully saved to S3", "file": file_name})
    }