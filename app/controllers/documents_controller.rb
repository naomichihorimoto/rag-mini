class DocumentsController < ApplicationController
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

      if @documents.empty?
        @ai_answer = "申し訳ございませんが、ご質問に関連する文書が見つかりませんでした。"
        @used_documents = []
      else
        # 検索結果をLLMに渡して回答を生成
        puts "Documents found: #{@documents.length}"
        @documents.each_with_index do |doc, i|
          puts "Document #{i+1}: #{doc.title} (#{doc.content.length} chars)"
        end

        puts "Calling generate_ai_answer..."
        @ai_answer = Document.generate_ai_answer(@search_query, @documents)
        puts "AI Answer generated: #{@ai_answer[0..100]}..." if @ai_answer
        @used_documents = @documents
      end
      @answer_generated = true

    rescue => e
      Rails.logger.error "Answer generation error: #{e.message}"
      redirect_to documents_path, alert: 'AI回答の生成中にエラーが発生しました。Ollamaサービスが起動していることを確認してください。'
    end
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end
end
