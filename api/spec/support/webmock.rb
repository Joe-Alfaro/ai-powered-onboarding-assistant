# Every spec runs with real network access blocked, so no spec can reach a real external service
# (JWKS, storage, LLM providers). A spec that needs a local socket (see HangingServer) allows only
# that host and port.
require "webmock/rspec"

WebMock.disable_net_connect!
