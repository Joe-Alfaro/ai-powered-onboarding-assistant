# Development runs jobs on the default :async adapter, which doesn't read config/recurring.yml
# (only Solid Queue does, in production). So the dev server enqueues the development entries
# itself, each on its own schedule (R17: abandoned upload images are purged locally too).
if Rails.env.development? && defined?(Rails::Server)
  Rails.application.config.after_initialize do
    Rails.application.config_for(:recurring).each_value do |task|
      next unless task[:class]

      schedule = Fugit.parse(task[:schedule])
      Thread.new do
        loop do
          sleep [ schedule.next_time.to_t - Time.current, 1 ].max
          Rails.application.executor.wrap { task[:class].constantize.perform_later(*task[:args]) }
        end
      end
    end
  end
end
