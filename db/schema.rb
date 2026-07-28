# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_28_235720) do
  create_table "expenses", force: :cascade do |t|
    t.decimal "amount", precision: 20, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "expense_account_id", null: false
    t.date "incurred_on", null: false
    t.text "memo"
    t.integer "organization_id", null: false
    t.integer "paid_from_account_id", null: false
    t.datetime "updated_at", null: false
    t.string "vendor", null: false
    t.index ["expense_account_id"], name: "index_expenses_on_expense_account_id"
    t.index ["organization_id"], name: "index_expenses_on_organization_id"
    t.index ["paid_from_account_id"], name: "index_expenses_on_paid_from_account_id"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "login_code_digest"
    t.datetime "login_code_expires_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_identities_on_email", unique: true
  end

  create_table "invoices", force: :cascade do |t|
    t.decimal "amount", precision: 20, scale: 2, null: false
    t.string "client_name", null: false
    t.datetime "created_at", null: false
    t.date "due_date", null: false
    t.integer "organization_id", null: false
    t.integer "receivable_account_id", null: false
    t.integer "revenue_account_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_invoices_on_organization_id"
    t.index ["receivable_account_id"], name: "index_invoices_on_receivable_account_id"
    t.index ["revenue_account_id"], name: "index_invoices_on_revenue_account_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "plutus_accounts", force: :cascade do |t|
    t.boolean "contra", default: false
    t.datetime "created_at", precision: nil
    t.string "name"
    t.integer "tenant_id"
    t.string "type"
    t.datetime "updated_at", precision: nil
    t.index ["name", "type"], name: "index_plutus_accounts_on_name_and_type"
    t.index ["tenant_id"], name: "index_plutus_accounts_on_tenant_id"
  end

  create_table "plutus_amounts", force: :cascade do |t|
    t.integer "account_id"
    t.decimal "amount", precision: 20, scale: 10
    t.integer "entry_id"
    t.string "type"
    t.index ["account_id", "entry_id"], name: "index_plutus_amounts_on_account_id_and_entry_id"
    t.index ["entry_id", "account_id"], name: "index_plutus_amounts_on_entry_id_and_account_id"
    t.index ["type"], name: "index_plutus_amounts_on_type"
  end

  create_table "plutus_entries", force: :cascade do |t|
    t.integer "commercial_document_id"
    t.string "commercial_document_type"
    t.datetime "created_at", precision: nil
    t.date "date"
    t.string "description"
    t.datetime "updated_at", precision: nil
    t.index ["commercial_document_id", "commercial_document_type"], name: "index_entries_on_commercial_doc"
    t.index ["date"], name: "index_plutus_entries_on_date"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "identity_id", null: false
    t.string "name"
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_users_on_identity_id"
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "expenses", "organizations"
  add_foreign_key "invoices", "organizations"
  add_foreign_key "users", "identities"
  add_foreign_key "users", "organizations"
end
