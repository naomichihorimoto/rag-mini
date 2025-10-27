require 'net/http'
require 'json'
require 'pdf-reader'

namespace :rag do
  desc "Import all .md, .txt, and .pdf files from ingest directory into documents table with embeddings"
  task ingest: :environment do
    ingest_dir = Rails.root.join('ingest')

    unless Dir.exist?(ingest_dir)
      puts "Error: #{ingest_dir} directory not found"
      exit 1
    end

    # サポートする拡張子
    supported_extensions = %w[.md .txt .pdf]

    # ingestディレクトリ内の対象ファイルを検索
    files = Dir.glob(File.join(ingest_dir, '**', '*')).select do |file|
      File.file?(file) && supported_extensions.include?(File.extname(file).downcase)
    end

    if files.empty?
      puts "No .md, .txt, or .pdf files found in #{ingest_dir}"
      puts "Supported extensions: #{supported_extensions.join(', ')}"
      exit 1
    end

    puts "Found #{files.length} file(s) to process:"
    files.each { |file| puts "  - #{File.basename(file)}" }
    puts

    success_count = 0
    error_count = 0

    files.each do |file_path|
      begin
        puts "Processing #{File.basename(file_path)}..."

        # ファイルの拡張子に応じてコンテンツを読み込み
        file_extension = File.extname(file_path).downcase
        content = if file_extension == '.pdf'
          extract_text_from_pdf(file_path)
        else
          File.read(file_path)
        end

        if content.nil? || content.strip.empty?
          puts "  ❌ Error: No content extracted from #{File.basename(file_path)}"
          error_count += 1
          next
        end

        # ファイル名からタイトルを生成（拡張子を除く）
        title = File.basename(file_path, '.*')

        ollama_model = ENV['OLLAMA_EMBED_MODEL'] || 'nomic-embed-text'
        puts "  Generating embeddings using #{ollama_model}..."
        embedding = generate_embedding(content)

        if embedding.nil?
          puts "  ❌ Error: Failed to generate embedding for #{title}"
          error_count += 1
          next
        end

        puts "  Saving to database..."
        document = Document.find_or_initialize_by(title: title)
        document.content = content
        document.embedding = embedding

        if document.save
          puts "  ✅ Successfully imported: #{title}"
          puts "     Content length: #{content.length} characters"
          puts "     Embedding dimension: #{embedding.length}"
          success_count += 1
        else
          puts "  ❌ Error saving document: #{document.errors.full_messages.join(', ')}"
          error_count += 1
        end

      rescue => e
        puts "  ❌ Error processing #{File.basename(file_path)}: #{e.message}"
        error_count += 1
      end

      puts # 空行で区切り
    end

    puts "Import completed!"
    puts "✅ Success: #{success_count} files"
    puts "❌ Errors: #{error_count} files" if error_count > 0

    if error_count > 0
      puts "\nSome files failed to import. Check the errors above."
      exit 1
    end
  end

  desc "List all documents in the database"
  task list: :environment do
    documents = Document.all

    if documents.empty?
      puts "No documents found in database"
    else
      puts "Documents in database:"
      documents.each_with_index do |doc, index|
        puts "\n#{index + 1}. #{doc.title}"
        puts "   Created: #{doc.created_at}"
        puts "   Content: #{doc.content.truncate(100)}"
        puts "   Has embedding: #{doc.embedding.present?}"
      end
    end
  end

  desc "Clear all documents from the database"
  task clear: :environment do
    count = Document.count
    Document.destroy_all
    puts "Deleted #{count} documents from database"
  end

  desc "Test Ollama connection and embedding generation"
  task test_ollama: :environment do
    ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
    ollama_model = ENV['OLLAMA_EMBED_MODEL'] || 'nomic-embed-text'

    puts "Testing Ollama connection..."
    puts "Ollama URL: #{ollama_base_url}"
    puts "Model: #{ollama_model}"

    test_text = "Hello, this is a test."
    puts "Test text: #{test_text}"

    embedding = generate_embedding(test_text)

    if embedding
      puts "✅ Success! Generated embedding with #{embedding.length} dimensions"
      puts "First 5 values: #{embedding.first(5)}"
    else
      puts "❌ Failed to generate embedding"
      puts "Make sure:"
      puts "1. Ollama service is running"
      puts "2. #{ollama_model} model is installed"
      puts "3. Network connectivity is working"
    end
  end

  desc "Test LLM generation"
  task test_llm: :environment do
    ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
    ollama_gen_model = ENV['OLLAMA_GEN_MODEL'] || 'gemma3:4b'

    puts "Testing LLM generation..."
    puts "Ollama URL: #{ollama_base_url}"
    puts "Model: #{ollama_gen_model}"

    test_prompt = "こんにちは。簡単な挨拶をしてください。"
    puts "Test prompt: #{test_prompt}"

    begin
      response = Document.generate_llm_response(test_prompt)
      puts "✅ LLM Response: #{response}"
    rescue => e
      puts "❌ LLM Test failed: #{e.message}"
      puts "Make sure:"
      puts "1. Ollama service is running"
      puts "2. #{ollama_gen_model} model is installed"
      puts "3. Network connectivity is working"
    end
  end

  desc "Test full AI answer generation"
  task test_ai_answer: :environment do
    puts "Testing full AI answer generation..."

    # テスト用のクエリ
    test_query = "パスワードについて教えて"
    puts "Test query: #{test_query}"

    begin
      # セマンティック検索
      puts "1. Running semantic search..."
      documents = Document.semantic_search(test_query, limit: 3)
      puts "Found #{documents.length} documents"

      if documents.any?
        # AI回答生成
        puts "2. Generating AI answer..."
        answer = Document.generate_ai_answer(test_query, documents)
        puts "✅ AI Answer generated:"
        puts answer
      else
        puts "❌ No documents found for semantic search"
      end
    rescue => e
      puts "❌ Test failed: #{e.message}"
      puts e.backtrace.first(5)
    end
  end

  private

  def extract_text_from_pdf(pdf_path)
    puts "  Extracting text from PDF..."

    begin
      reader = PDF::Reader.new(pdf_path)
      text_content = ""

      reader.pages.each_with_index do |page, index|
        page_text = page.text.strip
        unless page_text.empty?
          text_content += "Page #{index + 1}:\n#{page_text}\n\n"
        end
      end

      if text_content.strip.empty?
        puts "  ⚠️  Warning: No text content found in PDF"
        return nil
      end

      puts "  ✅ Extracted text from #{reader.page_count} pages"
      text_content.strip

    rescue => e
      puts "  ❌ Error extracting text from PDF: #{e.message}"
      return nil
    end
  end

  def generate_embedding(text)
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
        puts "Error from Ollama API: #{response.code} #{response.message}"
        puts response.body
        return nil
      end
    rescue => e
      puts "Error connecting to Ollama: #{e.message}"
      puts "Ollama URL: #{ollama_base_url}"
      puts "Make sure:"
      puts "1. Ollama service is running (docker-compose up ollama)"
      puts "2. #{ollama_model} model is installed"
      puts "3. Network connectivity between containers is working"
      return nil
    end
  end
end
