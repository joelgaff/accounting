Rails.application.routes.draw do
  root "home#index"

  resource :session, only: %i[new create destroy] do
    get  :verify
    post :confirm
  end

  resources :invoices, only: %i[index new create]
  resources :expenses, only: %i[index new create]

  get "up" => "rails/health#show", as: :rails_health_check
end
