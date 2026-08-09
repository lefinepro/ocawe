require "kemal"

# Spec-only HTTP stub server.
#
# The runtime serves every endpoint through Kemal (`ACD::Kemal::App` mounts its
# routes on `Kemal::RouteHandler::INSTANCE` and starts them with `Kemal.run`),
# so specs that need a peer HTTP server build it with the same library instead
# of hand-wiring a bare `HTTP::Server` block.
#
# Two consequences of Kemal's design are handled here:
#
# * routing is process-global (`HTTP::Server::Context#route_lookup` always asks
#   `Kemal::RouteHandler::INSTANCE`), so every stub registers its routes under a
#   unique `/__spec/<hex>` prefix and they can never collide with the runtime's
#   routes or with another stub's;
# * `Kemal.run` binds the *global* configured port and traps signals, which a
#   spec must not do, so the stub binds its own OS-assigned loopback port and
#   serves `Kemal.config.handlers` - the very handler chain `Kemal.run` uses.
class KemalTestServer
  getter prefix : String

  @server : HTTP::Server?
  @port : Int32?

  def initialize
    @prefix = "/__spec/#{Random::Secure.hex(6)}"
  end

  def port : Int32
    @port || raise "KemalTestServer is not listening yet; call #listen first"
  end

  # Routes are declared through Kemal's global DSL (`get`/`post`), which is what
  # the runtime's endpoint modules use as well.
  def on_get(path : String, &block : HTTP::Server::Context -> _) : Nil
    get(route(path), &block)
  end

  def on_post(path : String, &block : HTTP::Server::Context -> _) : Nil
    post(route(path), &block)
  end

  # Full URL of a stub route, including the per-instance prefix and the port
  # the OS assigned.
  def url(path : String) : String
    "http://127.0.0.1:#{port}#{route(path)}"
  end

  def listen : Nil
    raise "KemalTestServer is already listening on port #{@port}" if @server

    Kemal.config.env = "test"
    Kemal.config.logging = false
    # Installs Kemal's own handler chain (init, HEAD fallback, exception
    # handler, websocket and route handlers) exactly once per process.
    Kemal.config.setup

    server = HTTP::Server.new(Kemal.config.handlers)
    @port = server.bind_tcp("127.0.0.1", 0).port
    @server = server
    spawn { server.listen }
    Fiber.yield
  end

  def close : Nil
    @server.try(&.close)
    @server = nil
  end

  private def route(path : String) : String
    raise Kemal::Exceptions::InvalidPathStartException.new("get", path) unless path.starts_with?('/')
    "#{@prefix}#{path}"
  end
end
