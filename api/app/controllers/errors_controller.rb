# Answers any path no other route matches, so unknown routes get the JSON envelope (R30).
class ErrorsController < ApplicationController
  skip_before_action :authenticate!

  def not_found
    raise ActionController::RoutingError, "no route matches"
  end
end
