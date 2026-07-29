Rails.application.routes.draw do
  root "dashboard#index"

  resource :session, only: %i[new create destroy] do
    get  :verify
    post :confirm
  end

  resources :invoices, only: %i[index new create]
  resources :expenses, only: %i[index new create]
  resources :accounts, only: %i[index]
  resources :contacts
  resource  :contact_import,           only: %i[new create]
  resource  :chart_of_accounts_import, only: %i[new create]
  resource  :import,   only: %i[new create]
  resource  :settings, only: %i[show update]

  get "up" => "rails/health#show", as: :rails_health_check
end
