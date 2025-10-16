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

  private

  def set_document
    @document = Document.find(params[:id])
  end
end
