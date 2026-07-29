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
  resources :journal_entries, only: %i[index show new create]
  resources :recurring_invoices do
    member { post :run_now }
  end
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

  get "reports" => "reports#index", as: :reports
  namespace :reports do
    resource :profit_and_loss,             only: :show
    resource :balance_sheet,               only: :show
    resource :trial_balance,               only: :show
    resource :general_ledger,              only: :show
    resource :accounts_receivable_aging,   only: :show
    resource :accounts_payable_aging,      only: :show
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
