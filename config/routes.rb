Rails.application.routes.draw do
  root "dashboard#index"

  resource :session, only: %i[new create destroy] do
    get  :verify
    post :confirm
  end

  resources :invoices, only: %i[index show new create] do
    resources :payments, only: %i[new create]
    member do
      get  :print
      get  :email
      post :send_email
    end
  end
  resources :expenses, only: %i[index show new create] do
    resources :payments, only: %i[new create]
  end
  resources :accounts, only: %i[index]
  resources :contacts
  resources :bank_transactions, only: %i[index] do
    member do
      post :match_invoice
      post :match_expense
      post :categorize
      post :ignore
    end
  end
  resource  :contact_import,           only: %i[new create]
  resource  :chart_of_accounts_import, only: %i[new create]

  # Xero-migration landing page + per-format Xero importers.
  # /imports              → index (landing page listing each importer)
  # /imports/invoices/new → Xero sales invoices CSV
  # /imports/bills/new    → Xero bills (purchases) CSV
  # /imports/bank/new     → bank statement CSV (both plain and Xero shape)
  resources :imports, only: :index
  namespace :imports do
    resource :invoices, only: %i[new create]
    resource :bills,    only: %i[new create]
    resource :bank,     only: %i[new create]
  end

  resource  :settings, only: %i[show update]
  resources :tax_rates

  get "reports"                => "reports#index",           as: :reports
  get "reports/profit_and_loss" => "reports#profit_and_loss", as: :profit_and_loss_report
  get "reports/balance_sheet"   => "reports#balance_sheet",   as: :balance_sheet_report
  get "reports/trial_balance"   => "reports#trial_balance",   as: :trial_balance_report
  get "reports/general_ledger"  => "reports#general_ledger",  as: :general_ledger_report

  get "up" => "rails/health#show", as: :rails_health_check
end
