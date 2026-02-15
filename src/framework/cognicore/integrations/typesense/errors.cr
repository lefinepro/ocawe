module CogniCore
  module Integrations
    module Typesense
      class Error < Exception
      end

      class ConfigError < Error
      end

      class ApiError < Error
        getter status_code : Int32?
        getter response_body : String?

        def initialize(message : String, @status_code : Int32? = nil, @response_body : String? = nil)
          super(message)
        end
      end
    end
  end
end
