module Cogni
  module MCP
    @@manager = Manager.new

    def self.manager : Manager
      @@manager
    end

    def self.parse_mcp_ref(ref : String) : {String, String}
      body = ref.sub(/^mcp:/, "")
      first = body.index(':')
      raise "invalid mcp reference: #{ref}" unless first
      server = body[0, first]
      name = body[first + 1, body.bytesize - first - 1]
      raise "invalid mcp reference: #{ref}" if server.empty? || name.empty?
      {server, name}
    end
  end
end
