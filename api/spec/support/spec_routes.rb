# Lets a request spec mount controllers defined in the spec itself. The block replaces the app's
# routes for that example; the real routes are restored afterwards.
module SpecRoutes
  def draw_spec_routes(&)
    Rails.application.routes.draw(&)
  end
end

RSpec.configure do |config|
  config.include SpecRoutes, type: :request
  config.after(type: :request) { Rails.application.reload_routes! }
end
