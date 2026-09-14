module HasBalanceDue
  extend ActiveSupport::Concern

  included do
    has_many :payments, dependent: :restrict_with_error
  end

  def paid_amount  = payments.sum(:amount)
  def balance_due  = total - paid_amount
  def paid?        = balance_due <= 0
  def outstanding? = !paid?
end
