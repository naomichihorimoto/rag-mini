class AddEmbeddingToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :embedding, :vector, limit: ENV.fetch("VECTOR_DIM", 768).to_i
  end
end
