module CogniCore
  module Integrations
    module Typesense
      struct Config
        getter url : String
        getter api_key : String
        getter collection : String

        def initialize(@url : String, @api_key : String, @collection : String = "materials")
        end

        def self.from_env(env : Hash(String, String)) : self
          url = env["TYPESENSE_URL"]?.to_s.strip
          api_key = env["TYPESENSE_API_KEY"]?.to_s.strip
          collection = env["TYPESENSE_COLLECTION"]?.to_s.strip
          collection = "materials" if collection.nil? || collection.empty?

          raise ConfigError.new("TYPESENSE_URL is required") if url.nil? || url.empty?
          raise ConfigError.new("TYPESENSE_API_KEY is required") if api_key.nil? || api_key.empty?
          url = url.not_nil!
          api_key = api_key.not_nil!
          collection = collection.not_nil!

          Config.new(
            url: normalize_url(url),
            api_key: api_key,
            collection: collection,
          )
        end

        private def self.normalize_url(url : String) : String
          url.gsub(/\/+$/, "")
        end
      end
    end
  end
end
