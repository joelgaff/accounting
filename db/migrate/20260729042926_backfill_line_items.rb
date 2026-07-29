class BackfillLineItems < ActiveRecord::Migration[8.1]
  # Stub models frozen to the schema shape at the time of this migration,
  # so future model changes don't rot the backfill.
  class Invoice < ActiveRecord::Base; end
  class Expense < ActiveRecord::Base; end
  class LineItem < ActiveRecord::Base
    self.inheritance_column = :_type_disabled
  end

  def up
    Invoice.reset_column_information
    Expense.reset_column_information

    Invoice.find_each do |inv|
      subtotal = (inv.attributes["subtotal"] || inv.amount) || 0
      LineItem.create!(
        lineable_type: "Invoice",
        lineable_id:   inv.id,
        account_id:    inv.revenue_account_id,
        tax_rate_id:   inv.attributes["tax_rate_id"],
        description:   "Services rendered",
        quantity:      1,
        unit_amount:   subtotal
      )
    end

    Expense.find_each do |exp|
      subtotal = (exp.attributes["subtotal"] || exp.amount) || 0
      LineItem.create!(
        lineable_type: "Expense",
        lineable_id:   exp.id,
        account_id:    exp.expense_account_id,
        tax_rate_id:   exp.attributes["tax_rate_id"],
        description:   "Expense",
        quantity:      1,
        unit_amount:   subtotal
      )
    end
  end

  def down
    LineItem.where(lineable_type: %w[Invoice Expense]).delete_all
  end
end
