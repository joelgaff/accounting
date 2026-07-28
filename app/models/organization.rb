class Organization < ApplicationRecord
  has_many :users,    dependent: :destroy
  has_many :invoices, dependent: :restrict_with_error
  validates :name, presence: true
end
