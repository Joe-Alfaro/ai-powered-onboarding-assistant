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

  # One chat message in, the assistant's reply out (R1, R2, R3).
  namespace :chat do
    resources :messages, only: :create
  end

  # Consent, ID upload, the OCR draft and confirmation, and typed-in identity (R5, R10, R12, R17).
  resources :consents, only: :create
  resources :documents, only: %i[create show] do
    member do
      get :preview
      post :confirm
    end
  end
  # Where the user is in the flow and what they have finished (R8, R17).
  get "onboarding" => "onboardings#show"
  namespace :onboarding do
    resource :identity, only: :create
  end

  # Withdrawing consent and deleting the account hard-delete the user's data (R13). Neither takes
  # an ID: the user comes only from the token (R19).
  delete "consents" => "consents#destroy"
  resource :account, only: :destroy

  # Defines the root path route ("/")
  # root "posts#index"

  # Keep last: any unmatched path gets the JSON 404 envelope instead of a default error page (R30).
  match "*path", to: "errors#not_found", via: :all, format: false
end
