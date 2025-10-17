class DocumentsController < ApplicationController
  include ActionController::Live  # SSE用のモジュール

  before_action :set_document, only: [:show]

  def index
    @documents = Document.all.order(created_at: :desc)
    @search_query = params[:q]
  end

  def show
  end

  def search
    @search_query = params[:q]

    if @search_query.blank?
      redirect_to documents_path, alert: '検索クエリを入力してください'
      return
    end

    begin
      @documents = Document.semantic_search(@search_query)
      @search_performed = true

      render :index
    rescue => e
      Rails.logger.error "Search error: #{e.message}"
      redirect_to documents_path, alert: '検索中にエラーが発生しました。Ollamaサービスが起動していることを確認してください。'
    end
  end

  def answer
    @search_query = params[:q]

    if @search_query.blank?
      redirect_to documents_path, alert: '質問を入力してください'
      return
    end

    begin
      # セマンティック検索で関連文書を取得
      @documents = Document.semantic_search(@search_query, limit: 5)
      @used_documents = @documents
      @answer_generated = true

    rescue => e
      Rails.logger.error "Answer generation error: #{e.message}"
      redirect_to documents_path, alert: 'AI回答の生成中にエラーが発生しました。Ollamaサービスが起動していることを確認してください。'
    end
  end

  # ストリーミング回答生成
  def stream_answer
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'

    @search_query = params[:q]

    if @search_query.blank?
      render_sse_error("質問が入力されていません")
      return
    end

    begin
      # セマンティック検索で関連文書を取得
      documents = Document.semantic_search(@search_query, limit: 5)

      if documents.empty?
        render_sse_data("申し訳ございませんが、ご質問に関連する文書が見つかりませんでした。", true)
        return
      end

      # 参考文書情報を送信
      render_sse_event('documents', documents.map { |doc|
        { id: doc.id, title: doc.title, content: truncate_text(doc.content, 200) }
      })

      # ストリーミング回答生成を開始
      render_sse_event('answer_start', {})

      Document.generate_ai_answer_stream(@search_query, documents) do |chunk|
        puts "Streaming chunk received in controller: #{chunk[0..50]}..." if chunk && chunk.length > 0
        puts "Sending SSE data: #{chunk[0..30]}..." if chunk && chunk.length > 0
        render_sse_data(chunk, false)
      end

      render_sse_event('answer_complete', {})

    rescue => e
      Rails.logger.error "Streaming answer error: #{e.message}"
      render_sse_error("AI回答の生成中にエラーが発生しました: #{e.message}")
    ensure
      response.stream.close
    end
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  # SSE用のヘルパーメソッド
  def render_sse_data(data, is_final = false)
    json_data = {
      type: 'data',
      content: data,
      final: is_final
    }.to_json

    response.stream.write("data: #{json_data}\n\n")

    # ActionController::Liveの場合の適切なflush
    begin
      response.stream.flush
    rescue NoMethodError
      # flush メソッドがない場合は何もしない
    end
  end

  def render_sse_event(event_type, data)
    json_data = {
      type: event_type,
      data: data
    }.to_json

    response.stream.write("data: #{json_data}\n\n")

    # ActionController::Liveの場合の適切なflush
    begin
      response.stream.flush
    rescue NoMethodError
      # flush メソッドがない場合は何もしない
    end
    response.stream.flush if response.stream.respond_to?(:flush)

  end

  def render_sse_error(error_message)
    json_data = {
      type: 'error',
      message: error_message
    }.to_json

    response.stream.write("data: #{json_data}\n\n")

    # ActionController::Liveの場合の適切なflush
    begin
      response.stream.flush
    rescue NoMethodError
      # flush メソッドがない場合は何もしない
    end

    response.stream.close
    response.stream.flush if response.stream.respond_to?(:flush)
    response.stream.close
  end

  def truncate_text(text, length)
    text.length > length ? "#{text[0..length-1]}..." : text
  end
end
