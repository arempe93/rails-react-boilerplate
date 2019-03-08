# TODO: change name to application name
YourApplication::Application.routes.draw do
  mount API::Base => '/api'

  mount GrapeSwaggerRails::Engine => '/docs'
  mount Sidekiq::Web => '/sidekiq'

  get '*path', to: 'react#index'
  root to: 'react#index'
end
