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

  # LLMを使用してAI回答を生成
  def self.generate_ai_answer(question, relevant_documents)
    puts "=== generate_ai_answer called ==="
    puts "Question: #{question}"
    puts "Documents count: #{relevant_documents.length}"

    return "関連する文書が見つかりませんでした。" if relevant_documents.empty?

    begin
      # 関連文書のコンテンツを結合
      puts "Building context from documents..."
      context = relevant_documents.map.with_index(1) do |doc, index|
        "【文書#{index}: #{doc.title}】\n#{doc.content}"
      end.join("\n\n")
      puts "Context length: #{context.length} characters"

      # プロンプトを構築
      puts "Building prompt..."
      prompt = build_answer_prompt(question, context)
      puts "Prompt length: #{prompt.length} characters"

      # LLMに送信して回答を生成
      puts "Calling generate_llm_response..."
      result = generate_llm_response(prompt)
      puts "LLM response received: #{result[0..100]}..." if result
      return result
    rescue => e
      puts "Error in generate_ai_answer: #{e.message}"
      puts e.backtrace
      return "AI回答の生成中にエラーが発生しました: #{e.message}"
    end
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

  # LLM回答生成用のプロンプトを構築
  def self.build_answer_prompt(question, context)
    <<~PROMPT
      あなたは文書検索システムのAIアシスタントです。
      ユーザーの質問に対して、提供された文書の内容に基づいて正確で役立つ回答を提供してください。

      # 注意事項
      - 提供された文書の内容のみを根拠として回答してください
      - 文書に記載されていない情報は推測しないでください
      - 回答は日本語で、わかりやすく丁寧に説明してください
      - 関連する文書名も回答に含めてください

      # 関連文書
      #{context}

      # ユーザーの質問
      #{question}

      # 回答
    PROMPT
  end

  # OllamaのLLMに対してテキスト生成リクエストを送信
  def self.generate_llm_response(prompt)
    require 'net/http'
    require 'json'

    puts "=== generate_llm_response called ==="

    # Docker環境では環境変数からOllama URLとモデルを取得
    ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
    ollama_gen_model = ENV['OLLAMA_GEN_MODEL'] || 'gemma3:4b'

    puts "Ollama URL: #{ollama_base_url}"
    puts "Model: #{ollama_gen_model}"

    # Ollama API のエンドポイント
    uri = URI("#{ollama_base_url}/api/generate")
    puts "API Endpoint: #{uri}"

    # リクエストボディ
    request_body = {
      model: ollama_gen_model,
      prompt: prompt,
      stream: false,
      options: {
        temperature: 0.3,  # 創造性を抑えて正確性を重視
        top_p: 0.8,
        num_predict: 1000  # Ollamaでは max_tokens ではなく num_predict を使用
      }
    }.to_json

    puts "Request body size: #{request_body.length} bytes"

    # HTTPリクエストを送信
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120 # LLMは時間がかかるので長めに設定

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = request_body

    puts "Sending request to Ollama..."

    begin
      response = http.request(request)
      puts "Response received. Status: #{response.code}"

      if response.code == '200'
        puts "Success! Parsing response..."
        result = JSON.parse(response.body)
        answer = result['response'] || "回答を生成できませんでした。"
        puts "Generated answer length: #{answer.length} characters"
        return answer
      else
        error_msg = "Error from Ollama LLM API: #{response.code} #{response.message}"
        puts error_msg
        puts "Response body: #{response.body}"
        Rails.logger.error error_msg
        Rails.logger.error response.body
        return "LLMサービスとの通信中にエラーが発生しました。ステータス: #{response.code}"
      end
    rescue => e
      error_msg = "Error connecting to Ollama LLM: #{e.message}"
      puts error_msg
      puts "Error class: #{e.class}"
      puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
      Rails.logger.error error_msg
      Rails.logger.error "Ollama URL: #{ollama_base_url}"
      return "LLMサービスに接続できませんでした: #{e.message}"
    end
  end
end
