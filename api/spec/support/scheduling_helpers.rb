# Builds slots and bookings straight through the models, so specs can set up state without
# going through Scheduling::Booker.
module SchedulingHelpers
  ISO_8601_UTC = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z\z/

  def create_slot(starts_at: 2.days.from_now.utc.change(min: 0, sec: 0), length: 30.minutes)
    Slot.create!(starts_at: starts_at, ends_at: starts_at + length)
  end

  def create_booking(user_id:, slot: create_slot, status: "active")
    Booking.create!(user_id: user_id, slot: slot, status: status)
  end

  def active_bookings_on(slot)
    Booking.where(slot_id: slot.id, status: "active")
  end

  # Runs the block once per item on its own thread, all released at the same moment, and returns
  # the block results in item order. Each thread checks out its own database connection and
  # returns it through the executor when done.
  def in_parallel(items)
    ready = Queue.new
    go = Queue.new
    threads = items.map do |item|
      Thread.new do
        Thread.current.report_on_exception = false # the error re-raises from #value instead
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection # check out before the start signal, not during the race
          ready << true
          go.pop
          yield item
        end
      end
    end
    items.size.times { ready.pop }
    items.size.times { go << true }
    threads.map(&:value)
  end

  # Specs that run real threads can't share the example's transaction, and need a pool large
  # enough for every thread to hold a connection at once.
  def with_connection_pool_of(size)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(config.merge(max_connections: size))
    yield
  ensure
    ActiveRecord::Base.establish_connection(config)
  end
end

RSpec.configure do |config|
  config.include SchedulingHelpers
end
