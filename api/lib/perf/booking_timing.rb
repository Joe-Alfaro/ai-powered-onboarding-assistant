module Perf
  # R24: books an open slot and cancels it again, `runs` times, one at a time. Only the
  # POST /bookings requests are reported. Any booking the user already holds is cancelled first,
  # so each run is a fresh booking rather than a 409.
  class BookingTiming
    class Error < StandardError; end

    def initialize(client:, runs: 20)
      @client = client
      @runs = runs
    end

    def call
      cancel_existing
      Array.new(@runs) do
        slot_id = first_open_slot
        reply = @client.post_json("/bookings", slot_id: slot_id)
        booking_id = reply.body.dig("booking", "id")
        @client.delete("/bookings/#{booking_id}") if booking_id
        reply
      end
    end

    def self.success?(reply)
      reply.status == 201
    end

    private
      def cancel_existing
        @client.get("/bookings").body.fetch("bookings", []).each { |booking| @client.delete("/bookings/#{booking['id']}") }
      end

      def first_open_slot
        slot = @client.get("/slots").body.fetch("slots", []).first
        raise Error, "No open slots: run the seed (bin/rails db:seed) to add some" unless slot

        slot["id"]
      end
  end
end
