class Document < ApplicationRecord
  has_neighbors :embedding
end
