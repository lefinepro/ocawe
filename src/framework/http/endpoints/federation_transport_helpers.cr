module ACD
  module Kemal
    class App
      private def fetch_jsonld_activity(url : String, follow : Hash(String, JSON::Any)? = nil, expected_kind : String = "object") : Hash(String, JSON::Any)
        headers = ::HTTP::Headers{
          "Accept" => FEDERATION_JSONLD_CONTENT_TYPE,
        }
        signed = build_signature_headers("get", url, "")
        signed.each { |k, v| headers[k] = v }
        response = ::HTTP::Client.get(url, headers: headers)
        raise "HTTP #{response.status_code} GET #{url}" unless response.status_code >= 200 && response.status_code < 300
        parsed = JSON.parse(response.body).as_h?
        raise "invalid JSON-LD from #{url}" unless parsed
        if error = validate_contextual_federation_object(parsed, expected_kind: expected_kind)
          raise "invalid JSON-LD from #{url}: #{error}"
        end
        parsed
      end

      private def deliver_activity!(url : String, activity : Hash(String, JSON::Any)) : Nil
        payload = activity.to_json
        headers = ::HTTP::Headers{
          "Content-Type" => FEDERATION_JSONLD_CONTENT_TYPE,
        }
        signed = build_signature_headers("post", url, payload)
        signed.each { |k, v| headers[k] = v }
        response = ::HTTP::Client.post(url, headers: headers, body: payload)
        raise "HTTP #{response.status_code} POST #{url}" unless response.status_code >= 200 && response.status_code < 300
      end

      private def build_signature_headers(method : String, url : String, _body : String) : Hash(String, String)
        return {} of String => String unless @settings.federation.signatures_required
        uri = URI.parse(url)
        host = uri.host.to_s
        host = "#{host}:#{uri.port}" if uri.port
        path = uri.path.empty? ? "/" : uri.path
        path += "?#{uri.query}" if uri.query
        date = Time.utc.to_s("%a, %d %b %Y %H:%M:%S GMT")
        headers_list = "(request-target) host date"
        signing_string = "(request-target): #{method.downcase} #{path}\nhost: #{host}\ndate: #{date}"
        signature_b64 = sign_string(signing_string)
        signature = %(keyId="#{@settings.federation.local_key_id}",algorithm="rsa-sha256",headers="#{headers_list}",signature="#{signature_b64}")
        {"Date" => date, "Host" => host, "Signature" => signature}
      end

      private def sign_string(data : String) : String
        key_path = @settings.federation.local_private_key_path
        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run(
          "openssl",
          args: ["dgst", "-sha256", "-sign", key_path],
          input: IO::Memory.new(data),
          output: output,
          error: errors
        )
        raise "openssl sign failed: #{errors.to_s.strip}" unless status.success?
        Base64.strict_encode(output.to_slice)
      end

      private def valid_http_signature?(env, body : Hash(String, JSON::Any)) : Bool
        return true unless @settings.federation.signatures_required
        signature_header = env.request.headers["Signature"]?.to_s
        return false if signature_header.nil? || signature_header.empty?
        date_header = env.request.headers["Date"]?.to_s
        return false if date_header.nil? || date_header.empty?
        actor = body["actor"]?.try(&.as_s?).to_s
        return false if actor.empty?
        follow = @federation_store.list_following.find { |entry| entry["remote_actor"]?.try(&.as_s?) == actor }
        return false unless follow
        public_key_pem = follow["remote_public_key_pem"]?.try(&.as_s?).to_s
        return false if public_key_pem.empty?
        signature_map = parse_signature_header(signature_header)
        signature_value = signature_map["signature"]?.to_s
        return false if signature_value.empty?
        headers_value = signature_map["headers"]?.to_s
        headers_order = headers_value.empty? ? ["(request-target)"] : headers_value.split(' ')
        signing_lines = [] of String
        headers_order.each do |header_name|
          normalized = header_name.downcase
          value = if normalized == "(request-target)"
                    "#{env.request.method.downcase} #{env.request.path}"
                  elsif normalized == "host"
                    env.request.headers["Host"]?.to_s
                  else
                    env.request.headers[header_name]? || env.request.headers[header_name.capitalize]? || env.request.headers[normalized]?
                  end
          return false if value.nil? || value.to_s.empty?
          signing_lines << "#{normalized}: #{value}"
        end
        signing_string = signing_lines.join("\n")
        signature_data = Base64.decode_string(signature_value)
        verify_signature(signing_string, signature_data, public_key_pem)
      rescue
        false
      end

      private def verify_signature(data : String, signature_data : String, public_key_pem : String) : Bool
        key_path = ""
        data_path = ""
        sig_path = ""
        suffix = Random.rand(UInt64::MAX).to_s(16)
        tmp_dir = ENV["TMPDIR"]? || "/tmp"
        key_path = "#{tmp_dir}/cogni-fed-key-#{suffix}.pem"
        data_path = "#{tmp_dir}/cogni-fed-data-#{suffix}.txt"
        sig_path = "#{tmp_dir}/cogni-fed-signature-#{suffix}.bin"

        File.write(key_path, public_key_pem)
        File.write(data_path, data)
        File.open(sig_path, "wb") { |f| f << signature_data }

        status = Process.run(
          "openssl",
          args: ["dgst", "-sha256", "-verify", key_path, "-signature", sig_path, data_path],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        )
        status.success?
      ensure
        if kp = key_path
          File.delete(kp) if !kp.empty? && File.exists?(kp)
        end
        if dp = data_path
          File.delete(dp) if !dp.empty? && File.exists?(dp)
        end
        if sp = sig_path
          File.delete(sp) if !sp.empty? && File.exists?(sp)
        end
      end

      private def parse_signature_header(raw : String) : Hash(String, String)
        values = {} of String => String
        raw.split(",").each do |part|
          kv = part.split("=", 2)
          next if kv.size != 2
          key = kv[0].strip
          value = kv[1].strip
          if value.starts_with?('"') && value.ends_with?('"') && value.size >= 2
            value = value[1, value.size - 2]
          end
          values[key] = value
        end
        values
      end

      private def workflow_id_from_actor(actor : String) : String
        return "" if actor.strip.empty?
        parts = actor.split('/').reject(&.empty?)
        return "" if parts.empty?

        actor_index = -1
        parts.each_with_index do |part, idx|
          actor_index = idx if part == "actors"
        end
        if actor_index >= 0 && actor_index + 1 < parts.size
          return parts[actor_index + 1]
        end
        parts.last? || ""
      end

      private def resolve_local_actor(body : Hash(String, JSON::Any)) : String
        pick_first_non_empty(
          body["actor"]?.try(&.as_s?),
          body["local_actor"]?.try(&.as_s?),
          body["local_actor_id"]?.try(&.as_s?),
        )
      end

      private def resolve_remote_actor(body : Hash(String, JSON::Any)) : String
        object = body["object"]?
        remote_from_object = if object_hash = object.try(&.as_h?)
                               object_hash["id"]?.try(&.as_s?) || object_hash["actor"]?.try(&.as_s?)
                             else
                               object.try(&.as_s?)
                             end
        pick_first_non_empty(
          remote_from_object,
          body["remote_actor"]?.try(&.as_s?),
        )
      end

      private def infer_queue_from_actor(remote_actor : String) : String
        return "order-queue" if remote_actor.empty?
        tail = remote_actor.split('/').last?.to_s
        return "order-queue" if tail.empty?
        tail
      end

      private def pick_first_non_empty(*values : String?) : String
        values.each do |value|
          next unless value
          stripped = value.strip
          return stripped unless stripped.empty?
        end
        ""
      end
    end
  end
end
