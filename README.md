# rag-mini

簡単な文書をRAGで扱うためのアプリ

生成AIのランタイムにOllamaを用いることで、トークンコストを抑えています

## 環境構築

1. `docker compose build`
2. `docker compose up`
3. `docker compose exec web rails db:create`
4. `docker compose exec web rails db:migrate`

## LLMインストール

embeddingするためのモデルと、回答を生成するためのモデルをそれぞれインストールしてください

使用できるモデルは色々あるので、詳しくはOllama公式をご参照ください

例）

```
docker compose exec ollama ollama pull nomic-embed-text
docker compose exec ollama ollama pull gemma3:4b
```

## 文書のimport方法

```
# ingest/の全ファイルを取り込み（.mdもしくは.txt,.pdfファイル）
docker-compose exec web bundle exec rake rag:ingest

# 取り込まれた文書を確認
docker-compose exec web bundle exec rake rag:list
```

## 使用方法

ベクトル検索〜回答生成＆返却部分作ったら書きます
