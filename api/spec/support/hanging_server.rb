require "socket"

# A local TCP server that accepts connections and never answers, to prove a client times out
# for real instead of hanging. WebMock is told to let requests through to it.
class HangingServer
  def self.open
    server = new
    WebMock.disable_net_connect!(allow: "127.0.0.1:#{server.port}")
    yield server
  ensure
    WebMock.disable_net_connect!
    server&.close
  end

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @clients = []
    @thread = Thread.new do
      loop { @clients << @server.accept }
    rescue IOError, Errno::EBADF
      nil
    end
  end

  def port
    @server.addr[1]
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  def close
    @thread.kill
    @clients.each(&:close)
    @server.close
  end
end
