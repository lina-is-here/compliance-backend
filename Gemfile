# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.0'
gem 'pg'
# Use Puma as the app server
gem 'puma', '~> 5'
# Use Redis adapter to connect to Sidekiq
gem 'redis', '~> 4.0'
# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.1.0', require: false

# Kafka integration
gem 'racecar'
gem 'ruby-kafka'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'
gem 'rack', '>= 2.1.4'

# Swagger
gem 'rswag-api'
gem 'rswag-ui'

# Config YAML files for all environments
gem 'config'

# JSON API serializer
gem 'jsonapi-serializer'

# GraphQL support
gem 'graphql'
gem 'graphql-batch'

# Pundit authorization system
gem 'pundit'

# Alarms and notifications
gem 'exception_notification'
gem 'slack-notifier'

# Sidekiq - use reliable-fetch by Gitlab
gem 'sidekiq', '< 7'
gem 'gitlab-sidekiq-fetcher', require: 'sidekiq-reliable-fetch'

# Faraday to make requests easier
gem 'faraday'

# Helpers for models, pagination, mass import
gem 'friendly_id', '~> 5.2.4'
gem 'scoped_search'
gem 'will_paginate'
gem 'activerecord-import' # Substitute on upgrade to Rails 6
gem 'oj'
gem 'uuid'

# Prometheus exporter
gem 'prometheus_exporter', '>= 0.5'

# Logging, incl. CloudWatch
gem 'manageiq-loggers', '~> 0.6.0'

# Parsing OpenSCAP reports library
gem 'openscap_parser', '~> 1.2.0'

# RBAC service API
gem 'insights-rbac-api-client', '~> 1.0.0'

# REST API parameter type checking
gem 'stronger_parameters'

# Clowder config
gem 'clowder-common-ruby'

# Support for per request thread-local variables
gem 'request_store'

# Ruby 3 dependencies
gem 'cgi', ">= 0.3.1"
gem 'rexml'
gem 'webrick'

# Allows for tree structures in db 
gem 'ancestry'

group :development, :test do
  gem 'brakeman'
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'irb', '>= 1.2'
  gem 'minitest-reporters'
  gem 'minitest-stub-const'
  gem 'mocha'
  gem 'pry-byebug'
  gem 'pry-remote'
  gem 'rspec-rails'
  gem 'rswag-specs'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'shoulda-context'
  gem 'shoulda-matchers'
  gem 'silent_stream'
  gem 'simplecov'
  gem 'simplecov-cobertura', require: false
  gem 'webmock'
end

group :development do
  gem 'graphiql-rails'
  gem 'bullet'
  gem 'listen', '>= 3.0.5'
  gem 'pry-rails'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

group :development, :test do
  # load local gemfile
  local_gemfile = File.join(File.dirname(__FILE__), 'Gemfile.local')
  self.instance_eval(Bundler.read_file(local_gemfile)) if File.exist?(local_gemfile)
end
