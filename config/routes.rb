Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: 'users/registrations' }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check


  root to: 'home#index'

  get 'locale/:locale', to: 'locales#update', as: :set_locale

  resources :users, only: [:index, :new, :create, :edit, :update, :destroy]
  resources :users, path: 'admin/users', as: :admin_users, only: [:index, :new, :create, :edit, :update, :destroy]
  post 'admin/users/create', to: 'users#create', as: :admin_user_create

  namespace :professor do
    get 'dashboard', to: 'dashboard#index', as: :dashboard
    resources :classrooms do
      scope module: :classrooms do
        resources :enrollments, only: [:create, :destroy]
        resources :exercises,   only: [:create, :destroy, :show]
      end
    end
  end

  namespace :admin do
    get 'dashboard', to: 'dashboard#index'
    resources :users, except: [:show]
    resources :exercises, except: [:show] do
      post :duplicate, on: :member
    end
    resources :traffic_generators, except: [:show]
  end

  #devise_for :users

  resources :exercises do
    resources :submissions, only: [:new, :create]
    post 'test', to: 'test_runs#create', as: :test_run
  end
  get 'test_runs/:uuid', to: 'test_runs#show', as: :test_run
  resources :submissions, only: [:index, :show]

  # Student-facing: self-enrollment classrooms listing + join
  resources :classrooms, only: [:index, :show] do
    post :enroll, on: :member
  end

  #get 'admin/dashboard', to: 'admin#dashboard'
  get 'exercises/:exercise_id/run', to: 'submissions#run', as: 'run_exercise'

  # ActionCable WebSocket endpoint
  mount ActionCable.server => '/cable'

  # Internal callback from p4exec execution service
  namespace :internal do
    post 'exec_callback', to: 'exec_callbacks#create'
    post 'game_session_callback', to: 'game_session_callbacks#create'
  end

  resources :game_sessions, only: [:new, :create, :show, :destroy]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
