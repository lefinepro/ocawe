module Ocawe
  module MCP
    class Manager
      private def persist_dynamic_store : Nil
        list = @lock.synchronize do
          @dynamic_ids.compact_map { |id| @servers[id]? }
        end
        dir = File.dirname(@store_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
        File.write(@store_path, list.to_json)
      rescue
      end

      private def load_dynamic_store : Nil
        return unless File.exists?(@store_path)
        parsed = JSON.parse(File.read(@store_path)).as_a?
        return unless parsed

        parsed.each do |item|
          next unless hash = item.as_h?
          server = parse_server(hash)
          next if @lock.synchronize { @static_ids.includes?(server.id) }
          set_server(server, dynamic: true)
        end
      rescue
      end

      private def parse_server(body : AnyHash) : Ocawe::Config::MCPServerSettings
        id = body["id"]?.try(&.as_s?) || raise "server id required"
        transport = body["transport"]?.try(&.as_s?) || "http"
        command = body["command"]?.try(&.as_s?)
        args = body["args"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
        env = {} of String => String
        body["env"]?.try(&.as_h?).try(&.each { |k, v| env[k] = v.as_s? || v.raw.to_s })
        url = body["url"]?.try(&.as_s?)
        bearer_token = body["bearer_token"]?.try(&.as_s?)
        enabled = body["enabled"]?.try(&.as_bool?) != false
        Ocawe::Config::MCPServerSettings.new(
          id: id,
          transport: transport,
          command: command,
          args: args,
          env: env,
          url: url,
          bearer_token: bearer_token,
          enabled: enabled,
        )
      end

      private def json_any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
