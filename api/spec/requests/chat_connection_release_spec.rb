require "rails_helper"

# R22: a chat message spends most of its time waiting on the LLM, so it must not hold a database
# connection while it waits. Puma can then run more threads than the database has connections.
# Real Postgres and real threads, so no transactional test connection is shared between them.
RSpec.describe "POST /chat/messages database connection use", type: :request do
  self.use_transactional_tests = false

  let(:user_ids) { Array.new(4) { SecureRandom.uuid } }
  let(:pool) { ActiveRecord::Base.connection_pool }

  after do
    Assessment.where(user_id: user_ids).delete_all
    Message.joins(:conversation).where(conversations: { user_id: user_ids }).delete_all
    Conversation.where(user_id: user_ids).delete_all
  end

  def stub_llm(&during_call)
    adapter = FakeLlmAdapter.new.respond_by do
      during_call.call
      llm_output("ask-question", reply: "Happy to help with that.")
    end
    allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: adapter))
    adapter
  end

  def post_message(user_id)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/chat/messages", params: { message: "What happens on the first call?" }.to_json,
                                   headers: auth_headers(user_id).merge("Content-Type" => "application/json")
    session.response.status
  end

  def connection_use
    { leased: pool.active_connection? ? true : false, busy: pool.stat[:busy] }
  end

  def chat_in_new_thread(user_id)
    Thread.new { Rails.application.executor.wrap { post_message(user_id) } }.value
  end

  it "R22: holds no database connection while the LLM call is in flight" do
    seen = []
    stub_llm { seen << connection_use }

    expect(chat_in_new_thread(user_ids.first)).to eq(200)
    expect(seen).to eq([ { leased: false, busy: 0 } ])
    expect(Message.joins(:conversation).where(conversations: { user_id: user_ids.first }).count).to eq(2)
  end

  it "R22: hands back a connection something leased earlier in the request before calling the LLM" do
    seen = []
    stub_llm { seen << connection_use }
    allow(Consent::Ledger).to receive(:withdrawn?) do
      ActiveRecord::Base.lease_connection # sticky until released, unlike a model query's checkout
      false
    end

    expect(chat_in_new_thread(user_ids.first)).to eq(200)
    expect(seen).to eq([ { leased: false, busy: 0 } ])
    expect(Message.joins(:conversation).where(conversations: { user_id: user_ids.first }).count).to eq(2)
  end

  it "R22: lets more chat requests wait on the LLM at once than the pool has connections" do
    arrived = Queue.new
    release = Queue.new
    stub_llm do
      arrived << true
      # Every request must reach the LLM before any can finish; a held connection would stop that.
      Timeout.timeout(5) { release.pop }
    end

    statuses = with_connection_pool_of(1) do
      threads = user_ids.map { |user_id| Thread.new { post_message(user_id) } }
      Timeout.timeout(5) { user_ids.size.times { arrived.pop } }
      user_ids.size.times { release << true }
      threads.map(&:value)
    end

    expect(statuses).to all(eq(200))
  end
end
