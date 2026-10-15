# An error with its own JSON envelope (R30). Raise one from any layer to send the user a specific
# status, code, message and next actions, for example a 503 `llm_unavailable` offering
# `retry` and `manual_entry`. The message is shown to the user, so it must never hold personal data.
class ApiError < StandardError
  attr_reader :status, :code, :actions

  def self.forbidden
    new(status: 403, code: "forbidden", message: "You don't have access to this.")
  end

  def initialize(status:, code:, message:, actions: [])
    super(message)
    @status = status
    @code = code
    @actions = actions
  end

  def to_envelope
    { error: { code: code, message: message, actions: actions } }
  end
end
