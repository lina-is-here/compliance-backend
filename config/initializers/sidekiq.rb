Redis.exists_returns_integer = false # remove on sidekiq upgrade

sidekiq_config = lambda do |config|
  config.redis = {
    url: "redis://#{Settings.redis_url}",
    password: Settings.redis_password.present? ? Settings.redis_password : nil,
    ssl: Settings.redis_ssl,
    network_timeout: 5
  }
  config.options[:dead_timeout_in_seconds] = 2.weeks.to_i
  config.options[:interrupted_timeout_in_seconds] = 2.weeks.to_i
  Sidekiq::ReliableFetch.setup_reliable_fetch!(config)

  config.server_middleware do |chain|
    require 'prometheus_exporter/instrumentation'
    chain.add PrometheusExporter::Instrumentation::Sidekiq
  end
  config.on :startup do
    require 'prometheus_exporter/instrumentation'
    PrometheusExporter::Instrumentation::Process.start type: 'sidekiq'
  end
  config.death_handlers << PrometheusExporter::Instrumentation::Sidekiq.death_handler

  at_exit do
    PrometheusExporter::Client.default.stop(wait_timeout_seconds: 10)
  end
end

if $0.include?('sidekiq')
  Sidekiq.configure_server(&sidekiq_config)
end

if Rails.env != 'test'
  Sidekiq.configure_client(&sidekiq_config)
  Sidekiq.default_worker_options = { 'backtrace' => true, 'retry' => 3, 'unique' => true }
end
