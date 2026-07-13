require "base64"

module ACD
  module Kemal
    class App
      private def mount_file_endpoints
        post "/v1/files" do |env|
          filename, purpose, content = parse_file_upload(env)
          file = @file_service.create(filename, content, purpose)
          env.response.status_code = 201
          env.response.content_type = "application/json"
          file.to_json
        rescue ex
          json_error(env, 422, "file_upload_error", ex.message || "failed to upload file")
        end

        get "/v1/files" do |env|
          env.response.content_type = "application/json"
          {
            "object" => "list",
            "data"   => @file_service.list,
          }.to_json
        end

        get "/v1/files/:fileId" do |env|
          file_id = env.params.url["fileId"]
          file = @file_service.get(file_id)
          unless file
            next json_error(env, 404, "not_found", "file not found: #{file_id}")
          end

          env.response.content_type = "application/json"
          file.to_json
        end

        get "/v1/files/:fileId/content" do |env|
          file_id = env.params.url["fileId"]
          content = @file_service.content(file_id)
          unless content
            next json_error(env, 404, "not_found", "file not found: #{file_id}")
          end

          env.response.content_type = "application/octet-stream"
          content
        end

        delete "/v1/files/:fileId" do |env|
          file_id = env.params.url["fileId"]
          deleted = @file_service.delete(file_id)
          unless deleted
            next json_error(env, 404, "not_found", "file not found: #{file_id}")
          end

          env.response.content_type = "application/json"
          {
            "id"      => file_id,
            "object"  => "file",
            "deleted" => true,
          }.to_json
        end
      end

      private def parse_file_upload(env) : Tuple(String, String, String)
        content_type = env.request.headers["Content-Type"]? || ""
        if content_type.includes?("multipart/form-data")
          return parse_multipart_file_upload(env, content_type)
        end

        body = json_body(env)
        filename = body["filename"]?.try(&.as_s?) || body["name"]?.try(&.as_s?) || "upload.bin"
        purpose = body["purpose"]?.try(&.as_s?) || "assistants"
        content = body["content"]?.try(&.as_s?)
        if encoded = body["content_base64"]?.try(&.as_s?)
          content = Base64.decode_string(encoded)
        end
        raise "content or content_base64 is required" unless content
        {filename, purpose, content.not_nil!}
      end

      private def parse_multipart_file_upload(env, content_type : String) : Tuple(String, String, String)
        boundary = multipart_boundary(content_type)
        raise "multipart boundary is required" if boundary.empty?

        raw = env.request.body.try(&.gets_to_end).to_s
        marker = "--#{boundary}"
        filename = ""
        purpose = "assistants"
        content = nil.as(String?)

        raw.split(marker).each do |part|
          next if part.empty? || part.starts_with?("--")
          headers_raw, body = split_multipart_part(part)
          disposition = headers_raw.lines.find { |line| line.downcase.starts_with?("content-disposition:") } || ""
          name = multipart_disposition_value(disposition, "name")
          case name
          when "purpose"
            purpose = strip_multipart_body(body)
          when "file"
            filename = multipart_disposition_value(disposition, "filename")
            filename = "upload.bin" if filename.empty?
            content = strip_multipart_body(body)
          end
        end

        raise "file field is required" unless content
        {filename, purpose, content.not_nil!}
      end

      private def multipart_boundary(content_type : String) : String
        content_type.split(';').each do |part|
          key, value = part.split('=', 2)
          next unless key && value
          return value.strip.strip('"') if key.strip.downcase == "boundary"
        end
        ""
      end

      private def split_multipart_part(part : String) : Tuple(String, String)
        if idx = part.index("\r\n\r\n")
          return {part[0, idx], part[idx + 4, part.size - idx - 4]}
        end
        if idx = part.index("\n\n")
          return {part[0, idx], part[idx + 2, part.size - idx - 2]}
        end
        {"", part}
      end

      private def multipart_disposition_value(disposition : String, key : String) : String
        match = disposition.match(/(?:^|;\s*)#{Regex.escape(key)}="([^"]*)"/)
        match.try(&.[1]) || ""
      end

      private def strip_multipart_body(body : String) : String
        body.sub(/\r?\n\z/, "")
      end
    end
  end
end
