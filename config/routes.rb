Rails.application.routes.draw do
  root "dashboard#index"

  # Auth lives entirely at the Launchpad hub (see LaunchpadAuthentication).
  resources :invoices, only: %i[index show new create edit update] do
    member do
      get  :print
      get  :email
      post :send_email
      post :void
    end
  end
  %i[bills expenses deposits transfers].each do |kind|
    resources kind, only: %i[index show new create edit update] do
      member { post :void }
    end
  end
  resources :documents, only: [] do
    resources :payments, only: %i[new create]
  end
  resources :payments, only: :destroy
  resources :accounts, only: %i[index]
  resources :bank_accounts, except: %i[show destroy] do
    member do
      post :archive
      post :restore
    end
  end
  resources :contacts
  resources :journal_entries, only: %i[index show new create edit update] do
    member { post :void }
  end
  resources :recurring_invoices do
    member { post :run_now }
  end
  resources :bank_transactions, only: %i[index] do
    member do
      post :match
      post :allocate
      post :categorize
      post :transfer
      post :accept_suggestion
      post :ignore
      post :unmatch
    end
  end
  resources :bank_rules, except: :show
  resource  :contact_import,           only: %i[new create]
  resource  :chart_of_accounts_import, only: %i[new create]

  # Xero-migration landing page + per-format Xero importers.
  # /imports              → index (landing page listing each importer)
  # /imports/invoices/new → Xero sales invoices CSV
  # /imports/bills/new    → Xero bills (purchases) CSV
  # /imports/bank/new     → bank statement CSV (both plain and Xero shape)
  # /imports/journals/new → Xero Journal report (full ledger history)
  # /imports/tax_rates/new → tax rates CSV
  resources :imports, only: :index
  namespace :imports do
    resource :invoices, only: %i[new create]
    resource :bills,    only: %i[new create]
    resource :bank,     only: %i[new create], controller: "bank"
    resource :journals, only: %i[new create]
    resource :tax_rates, only: %i[new create]
  end

  resource  :settings, only: %i[show update]
  resources :tracking_categories, except: :show, path: "settings/tracking_categories"
  resource  :bank_feed, only: %i[show create update destroy], path: "settings/bank_feed" do
    post :sync
  end
  resources :tax_rates

  get "reports" => "reports#index", as: :reports
  namespace :reports do
    resource :profit_and_loss,             only: :show
    resource :profit_and_loss_by_tracking, only: :show
    resource :balance_sheet,               only: :show
    resource :trial_balance,               only: :show
    resource :general_ledger,              only: :show
    resource :accounts_receivable_aging,   only: :show
    resource :accounts_payable_aging,      only: :show
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
