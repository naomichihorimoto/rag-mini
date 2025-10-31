FROM python:3.11-slim

WORKDIR /app

# 必要ライブラリ
RUN pip install --no-cache-dir \
    torch sentence-transformers fastapi uvicorn[standard] numpy sentencepiece protobuf

# GLuCoSE-base-ja は初回起動時に自動ダウンロードされる
COPY . /app

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
