module Chat
  # POST /chat/messages (R1, R2, R3, R13, R16). The user comes only from the token. Internal action
  # names map to the wire vocabulary the web reads here, and nowhere else.
  class MessagesController < ApplicationController
    WIRE_ACTIONS = { "try_again" => "retry", "continue_manually" => "manual_entry" }.freeze
    LLM_UNAVAILABLE_MESSAGE = "The assistant isn't available right now. You can try again, or " \
                              "continue by filling in the form yourself.".freeze

    rescue_from Chat::ConsentWithdrawn do |error|
      render_error(error, ApiError.new(status: 403, code: "consent_withdrawn",
                                       message: "You've withdrawn consent, so the assistant can't process messages."))
    end

    rescue_from Llm::Error do |error|
      render_error(error, ApiError.new(status: 503, code: error.code, message: LLM_UNAVAILABLE_MESSAGE,
                                       actions: wire_actions(error.actions)))
    end

    def create
      result = Chat::Orchestrator.new(user_id: current_user_id, llm_client: Llm::Client.from_env)
                                 .handle(message: params[:message], booking_id: id_param(:booking_id),
                                         slot_id: id_param(:slot_id), cancel: params[:cancel] == true)

      render json: result.to_h.merge(actions: wire_actions(result.actions))
    end

    private

    def wire_actions(actions)
      actions.map { |action| WIRE_ACTIONS.fetch(action, action) }
    end

    def id_param(name)
      value = params[name]
      value if value.is_a?(String) && value.present?
    end
  end
end
