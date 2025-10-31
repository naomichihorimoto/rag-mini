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

  # ストリーミング形式でAI回答を生成
  def self.generate_ai_answer_stream(question, relevant_documents, &block)
    puts "=== generate_ai_answer_stream called ==="
    puts "Question: #{question}"
    puts "Documents count: #{relevant_documents.length}"

    if relevant_documents.empty?
      yield "関連する文書が見つかりませんでした。"
      return
    end

    begin
      # 関連文書のコンテンツを結合
      context = relevant_documents.map.with_index(1) do |doc, index|
        "【文書#{index}: #{doc.title}】\n#{doc.content}"
      end.join("\n\n")

      # プロンプトを構築
      prompt = build_answer_prompt(question, context)

      # ストリーミングでLLM回答を生成
      generate_llm_response_stream(prompt, &block)
    rescue => e
      puts "Error in generate_ai_answer_stream: #{e.message}"
      yield "AI回答の生成中にエラーが発生しました: #{e.message}"
    end
  end

  private

  # Ollamaを使用してベクトル埋め込みを生成
  def self.generate_embedding(text)
    require 'net/http'
    require 'json'

    uri = URI(ENV['EMBED_API_URL'] || 'http://localhost:8000/embed')

    # リクエストボディ
    request_body = {
      text: text
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
      以下の文書から質問に答えてください。文書にない情報は推測しないでください。

      文書:
      #{context}

      質問: #{question}

      回答:
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
        temperature: 0.1,      # より低い温度で一貫性を重視
        top_p: 0.5,           # より集中的な選択
        num_predict: 300,     # 短めの回答（300トークン）
        num_ctx: 1024,        # コンテキストウィンドウを小さく
        stop: ["。\n\n", "\n\n参考文書", "\n\n質問:"]  # 早期終了条件
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

  # ストリーミング形式でOllamaのLLMに対してテキスト生成リクエストを送信
  def self.generate_llm_response_stream(prompt, &block)
    require 'net/http'
    require 'json'

    puts "=== generate_llm_response_stream called ==="

    # Docker環境では環境変数からOllama URLとモデルを取得
    ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
    ollama_gen_model = ENV['OLLAMA_GEN_MODEL'] || 'gemma3:4b'

    puts "Ollama URL: #{ollama_base_url}"
    puts "Model: #{ollama_gen_model}"

    # Ollama API のエンドポイント
    uri = URI("#{ollama_base_url}/api/generate")
    puts "API Endpoint: #{uri}"

    # リクエストボディ（ストリーミング有効）
    request_body = {
      model: ollama_gen_model,
      prompt: prompt,
      stream: true,  # ストリーミングを有効化
      options: {
        temperature: 0.1,
        top_p: 0.5,
        num_predict: 300,
        num_ctx: 1024,
        stop: ["。\n\n", "\n\n参考文書", "\n\n質問:"]
      }
    }.to_json

    puts "Request body size: #{request_body.length} bytes"

    # HTTPリクエストを送信
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = request_body

    puts "Sending streaming request to Ollama..."

    begin
      http.request(request) do |response|
        puts "Streaming response received. Status: #{response.code}"

        if response.code == '200'
          puts "Starting to read streaming response body..."
          buffer = ""
          chunk_count = 0
          response.read_body do |chunk|
            chunk_count += 1
            puts "Received chunk #{chunk_count}: #{chunk.length} bytes"
            puts "Chunk content: #{chunk[0..200]}#{'...' if chunk.length > 200}"
            buffer += chunk
            lines = buffer.split("\n")
            buffer = lines.pop || "" # 最後の不完全な行は保持

            # チャンク自体がJSONの場合もあるので、直接解析を試す
            if !chunk.strip.empty?
              puts "Processing chunk directly: #{chunk[0..100]}#{'...' if chunk.length > 100}"

              begin
                json_data = JSON.parse(chunk)
                puts "Parsed JSON: response=#{json_data['response'] ? json_data['response'][0..50] : 'nil'}, done=#{json_data['done']}"
                if json_data['response'] && !json_data['response'].empty?
                  puts "Yielding response chunk: #{json_data['response'][0..50]}..."
                  yield json_data['response']
                end

                # 生成完了チェック
                if json_data['done']
                  puts "Streaming completed (done=true)"
                  break
                end
              rescue JSON::ParserError => e
                puts "JSON parse error on chunk: #{e.message}, chunk: #{chunk[0..100]}#{'...' if chunk.length > 100}"

                # 行ごとの解析も試す
                lines.each do |line|
                  next if line.strip.empty?
                  puts "Processing line: #{line[0..100]}#{'...' if line.length > 100}"

                  begin
                    json_data = JSON.parse(line)
                    puts "Parsed JSON: response=#{json_data['response'] ? json_data['response'][0..50] : 'nil'}, done=#{json_data['done']}"
                    if json_data['response'] && !json_data['response'].empty?
                      puts "Yielding response chunk: #{json_data['response'][0..50]}..."
                      yield json_data['response']
                    end

                    # 生成完了チェック
                    if json_data['done']
                      puts "Streaming completed (done=true)"
                      break
                    end
                  rescue JSON::ParserError => line_e
                    puts "JSON parse error on line: #{line_e.message}, line: #{line[0..100]}#{'...' if line.length > 100}"
                    next
                  end
                end
              end
            end
          end
          puts "Finished reading streaming response body"
        else
          error_msg = "Error from Ollama streaming API: #{response.code} #{response.message}"
          puts error_msg
          Rails.logger.error error_msg
          yield "LLMサービスとの通信中にエラーが発生しました。ステータス: #{response.code}"
        end
      end
    rescue => e
      error_msg = "Error connecting to Ollama streaming: #{e.message}"
      puts error_msg
      puts "Error class: #{e.class}"
      Rails.logger.error error_msg
      yield "LLMサービスに接続できませんでした: #{e.message}"
    end
  end
end
