require "http/client"
require "uri"
require "../config/settings"
require "./store"

module Cogni
  module Federation
    module Subscriptions
      extend self

      alias AnyHash = Hash(String, JSON::Any)

      struct Target
        getter name : String
        getter remote_actor : String
        getter queue : String

        def initialize(@name : String, @remote_actor : String, @queue : String)
        end
      end

      def ensure(
        settings : Cogni::Config::Settings,
        store : Cogni::Federation::Store::Base,
        name : String,
        *,
        actor_document : AnyHash? = nil
      ) : AnyHash
        target = parse_target(name)
        document = actor_document || fetch_actor_document(target.remote_actor, settings.federation.s2s_http_timeout_seconds)
        remote_actor = first_non_empty(
          document["id"]?.try(&.as_s?),
          target.remote_actor,
        )
        remote_inbox = first_non_empty(document["inbox"]?.try(&.as_s?))
        remote_outbox = first_non_empty(document["outbox"]?.try(&.as_s?))
        raise "remote actor missing outbox: #{remote_actor}" if remote_outbox.empty?

        public_key = document["publicKey"]?.try(&.as_h?) || {} of String => JSON::Any
        endpoints = document["endpoints"]?.try(&.as_h?) || {} of String => JSON::Any

        record = store.upsert_follow(
          local_actor: settings.federation.local_actor,
          remote_actor: remote_actor,
          queue: target.queue,
          capabilities: JSON.parse(%(["ticket"])),
          status: "active",
          remote_inbox: remote_inbox,
          remote_outbox: remote_outbox,
          remote_shared_inbox: first_non_empty(endpoints["sharedInbox"]?.try(&.as_s?)),
          remote_public_key_id: first_non_empty(public_key["id"]?.try(&.as_s?)),
          remote_public_key_pem: first_non_empty(public_key["publicKeyPem"]?.try(&.as_s?)),
          follow_activity_id: nil,
        )
        record["subscription_name"] = json_value(target.name)
        record["resolved_remote_actor"] = json_value(target.remote_actor)
        record
      end

      def parse_target(name : String) : Target
        normalized = name.strip
        raise "subscription name is required" if normalized.empty?

        if http_url?(normalized)
          remote_actor = normalized
          return Target.new(normalized, remote_actor, infer_queue_from_actor(remote_actor))
        end

        if normalized.starts_with?("@")
          value = normalized[1..]
          actor, domain = parse_handle(value, allow_domain_only: true)
          resolved_actor = actor.empty? ? "order-queue" : actor
          return Target.new(normalized, "https://#{domain}/actors/#{resolved_actor}", resolved_actor)
        end

        actor, domain = parse_handle(normalized, allow_domain_only: true)
        resolved_actor = actor.empty? ? "order-queue" : actor
        Target.new(normalized, "https://#{domain}/actors/#{resolved_actor}", resolved_actor)
      end

      def fetch_actor_document(url : String, timeout_seconds : Int32) : AnyHash
        headers = ::HTTP::Headers{
          "Accept" => "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\", application/activity+json, application/json",
        }
        uri = URI.parse(url)
        client = ::HTTP::Client.new(uri)
        timeout = timeout_seconds.seconds
        client.connect_timeout = timeout
        client.read_timeout = timeout
        path = uri.request_target
        path = "/" if path.empty?
        response = client.get(path, headers: headers)
        raise "HTTP #{response.status_code} GET #{url}" unless response.status_code >= 200 && response.status_code < 300
        parsed = JSON.parse(response.body).as_h?
        raise "invalid actor JSON-LD from #{url}" unless parsed
        parsed
      end

      private def parse_handle(value : String, allow_domain_only : Bool) : Tuple(String, String)
        if (idx = value.index('@'))
          actor = value[0, idx].strip
          domain = value[idx + 1, value.size - idx - 1].strip
          raise "invalid subscription handle: #{value}" if actor.empty? || domain.empty?
          validate_domain!(domain)
          return {actor, domain}
        end

        raise "invalid subscription handle: #{value}" unless allow_domain_only
        domain = value.strip
        validate_domain!(domain)
        {"", domain}
      end

      private def validate_domain!(domain : String) : Nil
        cleaned = domain.strip
        raise "invalid subscription domain: #{domain}" if cleaned.empty?
        raise "invalid subscription domain: #{domain}" if cleaned.includes?('/')
        raise "invalid subscription domain: #{domain}" if cleaned.starts_with?(".") || cleaned.ends_with?(".")
      end

      private def http_url?(value : String) : Bool
        value.starts_with?("http://") || value.starts_with?("https://")
      end

      private def infer_queue_from_actor(remote_actor : String) : String
        uri = URI.parse(remote_actor)
        path = uri.path.to_s
        return "order-queue" if path.ends_with?("/federation/actor")

        parts = path.split('/').reject(&.empty?)
        return "order-queue" if parts.empty?
        tail = parts.last?
        return "order-queue" if tail.nil? || tail.to_s.empty?
        tail.to_s
      rescue
        "order-queue"
      end

      private def first_non_empty(*values : String?) : String
        values.each do |value|
          next unless value
          stripped = value.strip
          return stripped unless stripped.empty?
        end
        ""
      end

      private def json_value(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
