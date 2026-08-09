module Ocawe
  module Federation
    # Resolution of `@name@fedi.internal` handles.
    #
    # `fedi.internal` is the reserved domain for peers that federate inside one
    # deployment (a compose project, a Kubernetes namespace, a test harness).
    # It is never a public domain, so a handle carrying it is resolved through a
    # local peer map instead of WebFinger:
    #
    #   1. `OCAWE_FEDERATION_INTERNAL_PEERS` - `name=base_url` pairs, comma or
    #      whitespace separated. Highest precedence so a deployment (or the E2E
    #      harness, which only learns its ports at spawn time) can pin peers
    #      without editing the Cawfile.
    #   2. `federation.internal_peers` in the Cawfile, same `name=base_url` form.
    #   3. `http://<name>.<internal_domain>:4111` - the service-DNS default, which
    #      is what a compose/Kubernetes network with per-service aliases resolves.
    #
    # Handles that carry any other domain are not touched here; they keep the
    # public `https://<domain>/actors/<name>` shape.
    module InternalDomain
      DEFAULT_DOMAIN = "fedi.internal"
      DEFAULT_PORT   =        4111
      PEERS_ENV_VAR  = "OCAWE_FEDERATION_INTERNAL_PEERS"

      # Parses `name=base_url` pairs. Entries without `=`, or with an empty name
      # or base url, are ignored rather than raising: a partially mistyped peer
      # map must not stop a runtime from booting, and the unresolved name simply
      # falls through to the service-DNS default.
      def self.parse_peers(entries : Enumerable(String)) : Hash(String, String)
        peers = {} of String => String
        entries.each do |entry|
          entry.split(/[,\s]+/).each do |pair|
            pair = pair.strip
            next if pair.empty?
            idx = pair.index('=')
            next unless idx
            name = pair[0, idx].strip
            base = pair[idx + 1, pair.size - idx - 1].strip
            next if name.empty? || base.empty?
            peers[name] = base.rstrip('/')
          end
        end
        peers
      end

      def self.peers_from_env(env_value : String?) : Hash(String, String)
        return {} of String => String unless env_value
        parse_peers([env_value])
      end

      # `@name@domain` / `name@domain` -> {name, domain}. Returns nil when the
      # value is not a handle (an IRI, or a bare domain without an actor name).
      def self.parse_handle(value : String) : Tuple(String, String)?
        raw = value.strip
        return nil if raw.empty?
        return nil if raw.starts_with?("http://") || raw.starts_with?("https://")
        raw = raw[1..] if raw.starts_with?('@')
        idx = raw.index('@')
        return nil unless idx
        name = raw[0, idx].strip
        domain = raw[idx + 1, raw.size - idx - 1].strip
        return nil if name.empty? || domain.empty?
        {name, domain}
      end

      def self.internal_handle?(value : String, domain : String = DEFAULT_DOMAIN) : Bool
        parsed = parse_handle(value)
        return false unless parsed
        parsed[1].downcase == domain.strip.downcase
      end

      # Base origin (scheme://host[:port]) for an internal peer name.
      def self.base_url(name : String, peers : Hash(String, String), domain : String = DEFAULT_DOMAIN) : String
        if mapped = peers[name]?
          return mapped.rstrip('/')
        end
        "http://#{name}.#{domain}:#{DEFAULT_PORT}"
      end

      # Actor IRI for an internal peer name.
      def self.actor_url(name : String, peers : Hash(String, String), domain : String = DEFAULT_DOMAIN) : String
        "#{base_url(name, peers, domain)}/actors/#{name}"
      end

      # Actor IRI for a `@name@fedi.internal` handle, or nil when the handle does
      # not belong to the internal domain.
      def self.resolve_actor(value : String, peers : Hash(String, String), domain : String = DEFAULT_DOMAIN) : String?
        parsed = parse_handle(value)
        return nil unless parsed
        name, handle_domain = parsed
        return nil unless handle_domain.downcase == domain.strip.downcase
        actor_url(name, peers, domain)
      end

      # `#+name: My Sender` -> `my-sender`. The actor identifier is a path
      # segment and a WebFinger local part, so it is restricted to characters
      # that survive both without escaping.
      def self.slug(name : String) : String
        slug = name.strip.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
        slug.empty? ? "server" : slug
      end
    end
  end
end
