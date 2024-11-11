# Terraform勉強-第32回：DockerイメージをAWS Lambdaでデプロイし、イメージのバージョンをハッシュ管理する(PythonコードをDockerイメージにしてECRにプッシュし、Lambda関数で使用)

githubリポジトリ：  
https://github.com/shu130/terraform-study32

## ディレクトリ

```plaintext
.
├── image_digest.txt      # Dockerイメージのハッシュファイル(自動生成)
├── docker
│   └── Dockerfile        # Lambda実行環境をDockerで定義
├── src
│   ├── app.py            # Lambda関数のPythonコード
│   └── requirements.txt  # Python外部ライブラリインストール用
└── terraform
    ├── ecr.tf            # Dockerイメージ格納用リポジトリ
    ├── lambda.tf         # Lambdaの構成とECRのプッシュ設定など
    ├── iam.tf            # Lambda関数のアクセス権限
    ├── s3.tf             # ハッシュファイルとLambda関数が生成するデータファイル用途
    ├── cloudwatch.tf     # Lambda関数のロググループの作成
    ├── provider.tf       # プロバイダやバージョンなど
    ├── variables.tf      # 変数を定義
    └── terraform.tfvars  # 変数の具体値
```

## Dockerファイルの作成（`docker/Dockerfile`）
Python3.11のランタイムを使用し、Lambda関数を実行するコンテナイメージを作成します。

```Dockerfile
# ./docker/Dockerfile

# ベースイメージとしてPython3.11を使用
FROM public.ecr.aws/lambda/python:3.11

# 必要なPythonパッケージのインストール
COPY src/requirements.txt .
RUN pip install -r requirements.txt

# アプリケーションコードの追加
COPY src/app.py ${LAMBDA_TASK_ROOT}

# Lambdaエントリーポイントの設定(app.pyのファイル名と関数名)
CMD ["app.lambda_handler"]
```
- `FROM public.ecr.aws/lambda/python:3.11`:   
   Lambdaのベースイメージを指定します。  
   Lambda用の公式Pythonイメージを使うことで、Lambda関数に必要な環境が整った状態からスタートできます。
- `COPY src/requirements.txt .`:   
   **Pythonのパッケージリストをコピー**します。  
   `requirements.txt`に、Lambda関数に必要なパッケージを記載し、Dockerイメージにコピーします。
- `RUN pip install -r requirements.txt`：    
  **Pythonのパッケージをインストール**します。`requirements.txt`に記載されたパッケージが、Lambda関数で利用できるようにインストールされます。
- `COPY src/app.py ${LAMBDA_TASK_ROOT}`:    
   **Lambda関数のコードをイメージに追加**しています。  
   `app.py`にLambda関数のPythonコードを書いて、Lambda環境（`LAMBDA_TASK_ROOT`）にコピーすることで、AWS Lambdaで実行できるようにします。
- `CMD ["app.lambda_handler"]`:    
   Lambda関数のエントリーポイントを指定します。  
   Lambdaがリクエストを受け取ったときに`app.py`ファイル内の`lambda_handler`関数が実行されるようにします。
---

## Lambda関数のPythonコード作成（`src/app.py`）

#### Python外部ライブラリ(`requirements.txt`):  
Lambda関数で利用する標準ライブラリ以外のPythonパッケージを記載します。  

```plaintext:src/requirements.txt
# ./src/requirements.txt

boto3==1.35.7
requests==2.32.3
```
- バージョンを指定しない場合はその時点の最新バージョンがインストールされる。
- **`boto3`**:  
  AWS SDKで、AWSサービスを操作するために使います。
- **`requests`**:  
  外部のAPIエンドポイントにHTTPリクエストを送るために使われます。
  - 外部APIからのデータ取得
  - 他のサービスとのデータ連携

#### Pythonコード(`app.py`):  
`requests`を使って外部APIからデータを取得し`boto3`を使ってS3にデータを保存します。

```python:./src/app.py
# ./src/app.py

import os   #=> osモジュールをインポート
import json #=>標準ライブラリ
import boto3
import requests
from datetime import datetime #=>標準ライブラリ

# S3クライアントを初期化
s3_client = boto3.client("s3")

def lambda_handler(event, context):
    # 1. 外部APIからデータを取得(今回はダミーデータを返す無料のAPIを使用します)
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
    bucket_name = os.getenv("S3_BUCKET_NAME") #=>lamdba.tfのなかの環境変数を取得   
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
```
- **`os`**：環境変数を取得するためのPythonの標準ライブラリで、`lamdba.tf`のなかの環境変数(`S3_BUCKET_NAME`)を取得します。
- **`json`**: Python標準ライブラリで、PythonのデータをJSON形式に変換したり、その逆の操作を行うために使用します。
- **`boto3`**: AWS SDK for Pythonです。ここではS3クライアントを作成するために使用します。
- **`requests`**: 外部APIにリクエストを送信するためのライブラリです。
- **`datetime`**: Python標準の日時ライブラリで、ファイル名に現在時刻を追加するために使用します。
- **`boto3.client("s3")`**: S3への接続を行うためのクライアントを初期化しています。これを通じてS3に対してデータの保存（アップロード）を行います。
- **`lambda_handler`関数**:  
  Lambda関数のエントリーポイントで、Lambdaが呼び出されると`event`と`context`という2つの引数を受け取ります。
  - **`event`**: Lambda関数をトリガーしたイベントデータが入ります。  
    例えば、API GatewayやS3のイベント通知で起動された場合、そのイベント情報が格納されます。
  - **`context`**: 実行環境に関する情報が格納されます。ログ出力やタイムアウト時間の取得などに使います。
- **`requests.get(api_url)`**: 指定したURLにGETリクエストを送信します。
- **`response.status_code`**:  
  リクエストの結果として、ステータスコードを取得します。  
  200はリクエストが成功したことを示しています。
- **`response.json()`**: レスポンスがJSON形式の場合、これでPythonの辞書型データに変換して取り出します。
- **`bucket_name`**: データを保存するS3バケット名です。
- **`file_name`**: ファイル名を指定します。  
 `datetime.now().strftime('%Y-%m-%d_%H-%M-%S')`を使って現在の日時をファイル名に含めています。
- **`s3_client.put_object`**: S3バケットにデータを保存するためのメソッドです。
  - **`Bucket`**: バケット名。
  - **`Key`**: 保存するファイルの名前。
  - **`Body`**: 保存するデータの内容を指定します。ここではJSON形式に変換したデータを指定。
  - **`ContentType`**: 保存するデータのコンテンツタイプ（JSON形式）。
---


## `./terraform/ecr.tf`
### 1. ECRリポジトリを作成

Lambdaで使用するDockerイメージを格納するためのリポジトリを作成する。

```hcl:./terraform/ecr.tf
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
}
```

## `./terraform/s3.tf`

### 1. S3バケット作成(Lambdaのアーティファクト用)

`aws_s3_bucket.lambda_artifacts`で、Lambdaのアーティファクトを保存するためのS3バケットを作成します。  
(アーティファクト：ハッシュファイルとLambda関数が生成するデータファイル)  
また、Lambda関数に対して、S3バケットへのアクセス権限を追加(S3バケットポリシー)

```hcl:./terraform/lambda.tf
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
```

### 2. ローカル変数の設定(`locals`ブロック)

`locals`ブロックで、コード内で共通して使う変数をまとめて定義します。  
S3バケット名、S3のディレクトリ、Pythonコードのディレクトリやハッシュファイル名を設定して、他のリソースで再利用しやすくします。

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

#--------------------
# ローカル変数
#--------------------
# 他リソースで使用する変数を定義
locals {
  s3_bucket      = aws_s3_bucket.lambda_artifacts.bucket #=> S3バケット名
  s3_key_prefix  = "lambda-python"
  s3_base_path   = "${local.s3_bucket}/${local.s3_key_prefix}"
  python_codedir = "${path.module}/../src"
  hash_file_name = "image_digest.txt"
}
```
- **`s3_bucket`**：デプロイ用ファイル（ハッシュファイルなど）を保存するS3バケットの名前です。
- **`s3_key_prefix`**：S3バケット内での保存先ディレクトリを指定しています。
- **`s3_base_path`**：S3バケットとディレクトリを合わせた完全なパス。後でS3のアップロード先やファイル取得に使用します。
- **`python_codedir`**：Lambda関数のコードがあるディレクトリ（`../src`）を指します。イメージビルド時に、このディレクトリの中身が対象となります。
- **`hash_file_name = "image_digest.txt"`**:   
  - このテキストファイル（`image_digest.txt`）にDockerイメージのハッシュ（データ識別情報）が自動で保存される。  
  (手動で作成ではなく、Terraformのコードが自動で生成・更新する)
  - LambdaにデプロイするDockerイメージが更新されるたびに、新しいハッシュが生成され、このファイルに保存される
  - **仕組みや生成方法、役割について**:   
    - このコードでは、`image_digest.txt`というファイル名を指定しています。このファイルにはDockerイメージのハッシュ（チェックサム）を保存します。
    - ハッシュは、特定のファイルやデータが変更されていないかどうかを確認するための「データの指紋」のようなもの。  
     同じデータから生成されるハッシュ値は常に同じですが、データが変更されるとハッシュ値も変わる。
  - **ハッシュファイルの自動生成**：
    - Terraformの`null_resource`リソース内で定義された一連のプロビジョナー（`provisioner "local-exec"`）がこのファイルを自動的に生成します。
    - この中でDockerイメージのビルドとプッシュが行われ、プッシュ後にイメージのハッシュ値が取得されてファイルに書き込まれます。
    - **実際のコマンド**：  
     ```bash
     docker inspect --format='{{index .RepoDigests 0}}' ${aws_ecr_repository.test_lambda.repository_url}:latest > ${local.hash_file_name}
     ```
    - このコマンドは、Dockerイメージの情報から「リポジトリダイジェスト」（ハッシュ情報）を取得し、`image_digest.txt`に保存してくれます。

   - **ハッシュファイルをS3にアップロード**：
     - ハッシュ情報をS3にアップロードすることにより、Lambda関数の最新バージョンを管理し、更新確認を行うことができます。
     - `null_resource`のプロビジョナーで次のようにアップロードしています：
     ```bash
     aws s3 cp ${local.hash_file_name} s3://${local.s3_base_path}/${local.hash_file_name} --content-type "text/plain"
     ```

   - **このファイル(`image_digest.txt`)が必要な理由**：
     - このハッシュファイルは、**Lambda関数のデプロイ管理**において重要な役割を果たします。  
     後述の `"aws_lambda_function"リソース`の`source_code_hash`パラメータにこのハッシュを使用すると、ハッシュの変化に応じてLambdaの再デプロイがトリガーされるため、更新管理が容易になる。

   - ##### 処理の流れ：
   > 1. **Dockerイメージをビルド**：コードが変更されたときに、Dockerイメージを最新の状態で再ビルドします。
   > 2. **イメージのハッシュを生成**：ビルドしたイメージのハッシュを`image_digest.txt`に保存します。
   > 3. **ハッシュをS3にアップロード**：S3にハッシュをアップロードしておき、Lambda関数の更新管理に使用します。

---

## `./terraform/iam.tf`

### 3. Lambda IAMロールとポリシーの作成

Lambda関数がS3とCloudWatch Logsにアクセスするために必要なIAMロールとポリシーを設定して、  
Lambda関数の実行結果をCloudWatch Logsに記録しつつ、S3にデータを保存できるようにします。

```hcl:./terraform/iam.tf
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

## S3バケットへのアクセス用途ポリシー
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
          "${aws_s3_bucket.lambda_artifacts.arn}",  #=> バケット自体へのアクセス権
          "${aws_s3_bucket.lambda_artifacts.arn}/*" #=> バケット内のオブジェクトへのアクセス権
        ]
      }
    ]
  })
}
```
---

## `./terraform/lambda.tf`

### 4. Lambda関数の作成

LambdaはECRに保存したDockerイメージを使用してデプロイします。  
Dockerイメージの更新をS3内のハッシュで検知し、自動的にLambdaの再デプロイが行われるように構成します。  
S3バケットの名前を環境変数としてLambda関数に渡します。

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

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
```
- **`function_name`**：Lambda関数の名前を指定します。
- **`package_type`**：`Image`を指定することで、コードはZIPファイルではなくコンテナイメージで管理されます。
- **`image_uri`**：ECRのリポジトリURLです。Lambdaはこのイメージを使用します。
- **`role`**：前のステップで作成したIAMロールをLambdaにアタッチします。
- **`source_code_hash`**：  
  このハッシュが変わると、Lambdaが自動的にデプロイを更新します。  
  S3のオブジェクトのハッシュを取得して比較します。
- **`S3_BUCKET_NAME`**：  
  環境変数に、`local.s3_bucket`を設定します。
  `./src/app.py`のなかで、`os.getenv("S3_BUCKET_NAME")`を使って、S3バケットの名前を取得します。


### 5. S3バケット内のイメージハッシュを取得

S3バケットに保存したDockerイメージのハッシュファイルを取得し、Lambda関数の更新トリガーとして使用します。
Lambdaの再デプロイの判断基準として、イメージの内容が変わったかどうかを確認します。

```hcl:./terraform/lambda.tf
#--------------------
# Lambda
#--------------------
# S3からDockerイメージのハッシュを取得するデータソース
data "aws_s3_object" "image_hash" {
  depends_on = [null_resource.lambda_build]

  bucket = local.s3_bucket
  key    = "${local.s3_key_prefix}/${local.hash_file_name}"
}
```
- **`depends_on`**：このブロックの前に、`null_resource.lambda_build`が実行される必要があることを指定しています。
- **`bucket`**：S3バケット名。
- **`key`**：S3バケット内のファイルパスです。

---

### 6. Dockerイメージのビルドとプッシュ(null_resource)

Lambdaコードの変更をトリガーとしてDockerイメージをビルド・プッシュする一連のローカルコマンドを実行させます。  
**`null_resource`とは？**：  
Terraformの**内部的なリソース**で**ローカルでコマンドを実行**するために使います。
```hcl:./terraform/lambda.tf
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
```
- **`resource "null_resource" "lambda_build"`**  
  これは、`lambda_build`という名前の`null_resource`を定義しています。  
  このリソース自体はAWSに何も作成せず、条件が満たされた場合にローカルでコマンドを実行させます。
- **`depends_on = [aws_ecr_repository.python_lambda]`**  
  ECRリポジトリが作成されてから実行されるようにします。    
  ECRリポジトリが存在しない状態でDockerイメージをプッシュするエラーを防ぎます。
- **`triggers`**：  
  `code_diff`にファイルのハッシュを指定して、  
  コード変更されたときにだけDockerイメージがビルド・プッシュされるように設定します。
- **`code_diff = sha256(...)`**：   
  `code_diff`という名前のトリガーを定義して、    
  Pythonコードがあるディレクトリ（`${local.python_codedir}`）内のファイルが変更されたかを判定します。
- **`for file in ...`** によって、そのリスト内のファイルを1つずつ順番に処理します。
- **コロン `:` の後ろ**で指定された **`filesha256("${local.python_codedir}/${file}")`** 処理が、各ファイルごとに実行され、SHA-256ハッシュ値が計算されます。　
- **`sha256(join("", [...] ))`**：    
  最後に、すべてのファイルのハッシュ値を連結し、1つのハッシュにまとめ、　　  
  ディレクトリ内のいずれかのファイルが変更されるとハッシュ値も変わり、トリガーが発動します。


#### 6-1. Dockerイメージのビルド

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

#--------------------
# null_resource
#--------------------

  # 1. Dockerイメージのビルド、イメージのタグ付け
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && docker build . -f docker/Dockerfile --platform linux/amd64 -t ${aws_ecr_repository.python_lambda.repository_url}:latest"
  }
```
- **`provisioner "local-exec"`**：
　- **`provisioner`**：Terraformのリソースが作成・更新されるときに実行する「追加のアクション」を定義します。  
　- **`local-exec`**： Terraformが実行されているローカル環境でコマンドを実行する。
　- Terraformのローカル環境で直接`docker build`コマンドを実行して、AWS ECRに登録するDockerイメージをビルドします。
   - **`${path.module}/..`**： 
   Terraformが現在実行しているファイルのディレクトリパスを表します。  
   `/..` を付けることで、一つ上のDockerfileやPythonのコードがあるディレクトリに移動します。
  - **`docker build . `**：  
    Dockerコマンドで、指定したDockerfileをもとにDockerイメージをビルドします。
  - **`-f docker/Dockerfile`**：  
  `-f` オプションでファイルを指定し、Dockerfileのパスを`docker/Dockerfile`としています。
  - **`--platform linux/amd64`**：  
  Lambdaで使えるプラットフォーム（Linuxの64ビット）でイメージをビルドするよう指定します。
  - **`-t ${aws_ecr_repository.python_lambda.repository_url}:latest`**：
    - **`-t`**は「タグ」を指定するオプションです。  
    Dockerイメージに名前とバージョン情報（タグ）を付けるために使われます。
    - **`${aws_ecr_repository.python_lambda.repository_url}:latest`**：  
    terraformで作成したAWS ECRリポジトリのURLを使って、`latest`としてタグ付けします。  
    ECRにこのイメージをプッシュするときに、このタグ付けを利用します。


#### 6-2. DockerイメージをECRにプッシュ

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

#--------------------
# null_resource
#--------------------

  # 2. DockerイメージをECRにプッシュ
  provisioner "local-exec" {
    command = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.python_lambda.repository_url} && docker push ${aws_ecr_repository.python_lambda.repository_url}:latest"
  }
```
 - **`aws ecr get-login-password --region ${var.region}`**：  
   - ECRへのログイン用のパスワードを取得して `docker login`に必要なパスワードを生成します。
   - AWSのリージョンを指定します。
 - **`docker login --username AWS --password-stdin ${aws_ecr_repository.python_lambda.repository_url}`**：  
   - DockerにECRリポジトリにログインさせます。
   - ECRにログインするために`AWS`というユーザー名を使用します（AWSの認証は基本的に`AWS`として行われます）。
   - `--password-stdin`：  
   パスワードを標準入力（`stdin`）から渡すためのオプションです。  
   `aws ecr get-login-password`で取得したパスワードが標準入力として渡されます。
   - `${aws_ecr_repository.python_lambda.repository_url}`： DockerイメージをプッシュするECRリポジトリのURLです。
 - **`docker push ${aws_ecr_repository.python_lambda.repository_url}:latest`**：  
   - `docker push`：  
     ローカルで作成したDockerイメージを指定したリモートリポジトリにアップロードします。
   - `${aws_ecr_repository.python_lambda.repository_url}:latest`：  
   プッシュするDockerイメージのリポジトリのURLを指定します。   
   `:latest` で、プッシュするタグを最新のイメージに指定します。

#### 6-3. Dockerイメージのハッシュを生成

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

#--------------------
# null_resource
#--------------------

  # 3. Dockerイメージのハッシュを生成し、ファイルに保存
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && docker inspect --format='{{index .RepoDigests 0}}' ${aws_ecr_repository.python_lambda.repository_url}:latest > ${local.hash_file_name}"
  }
```
- **`docker inspect`**：  
  Dockerイメージのハッシュ値を取得し、ファイルに保存します。  
  このハッシュ値を用いて、コードに変更があったかどうかを確認します。
- **`--format`** ：  
  取得した情報をカスタマイズした形式で表示するオプション。  
- **`{{index .RepoDigests 0}}`** ：  
　Docker イメージの **`RepoDigests`** フィールドの最初の要素を取得します。  
  このフィールドには、イメージの **ハッシュ値**（チェックサム）が格納されます。  
  このハッシュ値が、イメージが変更されていないかをチェックするために使用されます。
- **`> ${local.hash_file_name}`** ：  
  Dockerイメージのハッシュ値を **`local.hash_file_name`** で指定したファイル（`image_digest.txt`）に書き込みます。


#### 6-4. S3にハッシュファイルをアップロード

```hcl:./terraform/lambda.tf
# ./terraform/lambda.tf

#--------------------
# null_resource
#--------------------
  # 4. ハッシュファイルをS3にアップロードし、Lambda関数の更新に使用
  provisioner "local-exec" {
    command = "cd ${path.module}/.. && aws s3 cp ${local.hash_file_name} s3://${local.s3_base_path}/${local.hash_file_name} --content-type \"text/plain\""
  }
}
```
  - **`aws s3 cp`**:  
    AWS CLIコマンド、`s3 cp`でローカルファイルをS3にアップロード(コピー)します。
    - `${local.hash_file_name}`：  
      ローカルで生成されたハッシュファイル(`image_digest.txt`)です。
    - `s3://${local.s3_base_path}/${local.hash_file_name}`：  
      アップロード先のS3パスです。  
      `${local.s3_base_path}`は、S3バケットのパス、  
      `${local.hash_file_name}`はファイル名です。
    - `--content-type "text/plain"`：  
      このオプションで、S3にアップロードする際のコンテンツタイプとしてテキストを指定します。　　

### ./terraform/lambda.tf 完成

```hcl:./terraform/lambda.tf
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
```

## `terraform apply` 後の確認

`terraform state list` でリソース一覧を確認
```bash
$ terraform state list
data.aws_s3_object.image_hash
aws_cloudwatch_log_group.lambda_log
aws_ecr_repository.python_lambda
aws_iam_role.lambda_role
aws_iam_role_policy.lambda_cloudwatch_policy
aws_iam_role_policy.lambda_s3_policy
aws_lambda_function.python_lambda
aws_s3_bucket.lambda_artifacts
aws_s3_bucket_policy.lambda_bucket_policy
null_resource.lambda_build
random_id.suffix
```

## `AWS CLI`にてログ確認

### 1. CloudWatch Logsのロググループ一覧を確認

```bash
aws logs describe-log-groups
```

### 2. 最近のログストリームを取得

最新のログストリームを取得する。(`{Lambda関数名}`を実際のLambda関数名に置き換える)

```bash
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/{Lambda関数名}" \
    --order-by "LastEventTime" \
    --descending \
    --limit 1
```

### 3. ログストリームのログイベントを表示

取得したログストリーム名を使って、ログイベントを表示する。

```bash
aws logs get-log-events \
    --log-group-name "/aws/lambda/{Lambda関数名}" \
    --log-stream-name "{ログストリーム名}" \
    --limit 20
```

## `AWSコンソール画面`にて確認

ECR, Lambda, S3, CloudWatchにて確認する。

---
今回はここまでにしたいと思います。
