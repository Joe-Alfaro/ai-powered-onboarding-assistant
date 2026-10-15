Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Per-dependency status (R31). Public, for the uptime check.
  get "health" => "health#show"

  # Scheduling (R6, R7, R36). The user always comes from the token.
  resources :slots, only: :index
  resources :bookings, only: %i[index show create update destroy]

  namespace :admin do
    resources :slots, only: %i[create destroy]
  end

  # Defines the root path route ("/")
  # root "posts#index"

  # Keep last: any unmatched path gets the JSON 404 envelope instead of a default error page (R30).
  match "*path", to: "errors#not_found", via: :all, format: false
end
