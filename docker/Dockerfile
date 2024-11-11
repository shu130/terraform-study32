# ./docker/Dockerfile

# ベースイメージとしてPython3.11を使用
FROM public.ecr.aws/lambda/python:3.11

# 必要なPythonパッケージのインストール
COPY src/requirements.txt .
RUN pip install -r requirements.txt

# アプリケーションコードの追加
COPY src/app.py ${LAMBDA_TASK_ROOT}

# Lambdaエントリーポイントの設定
CMD ["app.lambda_handler"]