Rails.application.routes.draw do
  root "dashboard#index"

  resource :session, only: %i[new create destroy] do
    get  :verify
    post :confirm
  end

  resources :invoices, only: %i[index show new create] do
    resources :payments, only: %i[new create]
  end
  resources :expenses, only: %i[index show new create] do
    resources :payments, only: %i[new create]
  end
  resources :accounts, only: %i[index]
  resources :contacts
  resource  :contact_import,           only: %i[new create]
  resource  :chart_of_accounts_import, only: %i[new create]
  resource  :import,   only: %i[new create]
  resource  :settings, only: %i[show update]

  get "reports"                => "reports#index",           as: :reports
  get "reports/profit_and_loss" => "reports#profit_and_loss", as: :profit_and_loss_report
  get "reports/balance_sheet"   => "reports#balance_sheet",   as: :balance_sheet_report
  get "reports/trial_balance"   => "reports#trial_balance",   as: :trial_balance_report
  get "reports/general_ledger"  => "reports#general_ledger",  as: :general_ledger_report

  get "up" => "rails/health#show", as: :rails_health_check
end
