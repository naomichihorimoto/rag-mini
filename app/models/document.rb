class Document < ApplicationRecord
  has_neighbors :embedding

  # セマンティック検索メソッド
  def self.semantic_search(query, limit: 3)
    return none if query.blank?

    # クエリのベクトル埋め込みを生成
    query_embedding = generate_embedding(query)
    return none if query_embedding.nil?

    # neighbor gemを使用してベクトル類似度検索
    nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .limit(limit)
  end

  private

  # Ollamaを使用してベクトル埋め込みを生成
  def self.generate_embedding(text)
    require 'net/http'
    require 'json'

    # Docker環境では環境変数からOllama URLを取得
    ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
    ollama_model = ENV['OLLAMA_EMBED_MODEL'] || 'nomic-embed-text'

    # Ollama APIのエンドポイント
    uri = URI("#{ollama_base_url}/api/embeddings")

    # リクエストボディ
    request_body = {
      model: ollama_model,
      prompt: text
    }.to_json

    # HTTPリクエストを送信
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 60 # タイムアウトを60秒に設定

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = request_body

    begin
      response = http.request(request)

      if response.code == '200'
        result = JSON.parse(response.body)
        return result['embedding']
      else
        Rails.logger.error "Error from Ollama API: #{response.code} #{response.message}"
        Rails.logger.error response.body
        return nil
      end
    rescue => e
      Rails.logger.error "Error connecting to Ollama: #{e.message}"
      Rails.logger.error "Ollama URL: #{ollama_base_url}"
      return nil
    end
  end
end
