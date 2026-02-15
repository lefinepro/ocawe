require "http/client"
require "json"
module CogniCore
  module Integrations
    module Typesense
      class Client
        def initialize(@config : Config)
        end

        def get(path : String, allow_not_found : Bool = false) : JSON::Any?
          request("GET", path, allow_not_found: allow_not_found)
        end

        def post(path : String, body : String, content_type : String, allow_conflict : Bool = false) : String
          response = raw_request("POST", path, body: body, content_type: content_type)
          status = response.status_code
          if status == 409 && allow_conflict
            return response.body
          end
          return response.body if success_status?(status)

          raise ApiError.new(
            "Typesense POST failed for #{path}",
            status_code: status,
            response_body: response.body,
          )
        end

        private def request(method : String, path : String, allow_not_found : Bool = false) : JSON::Any?
          response = raw_request(method, path)
          status = response.status_code

          return nil if status == 404 && allow_not_found

          unless success_status?(status)
            raise ApiError.new(
              "Typesense request failed for #{path}",
              status_code: status,
              response_body: response.body,
            )
          end

          body = response.body.to_s.strip
          return JSON.parse("{}") if body.empty?
          JSON.parse(body)
        end

        private def raw_request(method : String, path : String, body : String? = nil, content_type : String? = nil) : HTTP::Client::Response
          headers = HTTP::Headers{
            "X-TYPESENSE-API-KEY" => @config.api_key,
          }
          headers["Content-Type"] = content_type.not_nil! if content_type

          url = "#{@config.url}#{path}"
          case method
          when "GET"
            HTTP::Client.get(url, headers: headers)
          when "POST"
            HTTP::Client.post(url, headers: headers, body: body.to_s)
          else
            raise Error.new("unsupported HTTP method: #{method}")
          end
        end

        private def success_status?(status : Int32) : Bool
          status >= 200 && status < 300
        end
      end
    end
  end
end
