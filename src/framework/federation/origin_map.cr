require "uri"

module Ocawe
  module Federation
    # Exact-host mapping for local development/federation test networks.
    # Logical ActivityPub URLs are never rewritten; callers use the returned
    # transport origin only for network I/O.
    class OriginMap
      def initialize(@mappings : Hash(String, String) = {} of String => String)
        @normalized = {} of String => String
        @mappings.each do |host, origin|
          key = host.strip.downcase
          raise ArgumentError.new("internal origin host must be exact") if key.empty? || key.includes?("*")
          uri = URI.parse(origin)
          raise ArgumentError.new("internal origin must be an absolute HTTP origin") unless uri.host && uri.scheme.in?("http", "https")
          raise ArgumentError.new("internal origin must not include a path") unless uri.path.empty? || uri.path == "/"
          @normalized[key] = origin.rstrip("/")
        end
      end

      def transport_origin(logical_origin : String) : String
        uri = URI.parse(logical_origin)
        host = uri.host
        return logical_origin unless host
        @normalized[host.downcase]? || logical_origin
      end

      def transport_uri(logical_uri : String) : URI
        uri = URI.parse(logical_uri)
        origin = transport_origin("#{uri.scheme}://#{uri.host}#{uri.port ? ":#{uri.port}" : ""}")
        mapped = URI.parse(origin)
        URI.new(scheme: mapped.scheme, user: mapped.user, password: mapped.password,
          host: mapped.host, port: mapped.port, path: uri.path, query: uri.query, fragment: uri.fragment)
      end
    end
  end
end
