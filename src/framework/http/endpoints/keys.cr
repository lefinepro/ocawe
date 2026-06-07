require "json"

module ACD
  module Kemal
    class App
      private KEY_STORE_PATH = "./.ocawe/keys.json"

      private def mount_keys_endpoints
        get "/v1/keys" do |env|
          env.response.content_type = "application/json"
          list_keys.to_json
        end

        get "/v1/keys/:keyName" do |env|
          key_name = env.params.url["keyName"]
          entry = get_key(key_name)

          unless entry
            env.response.status_code = 404
            next({error: {type: "not_found", message: "key not found: #{key_name}"}}.to_json)
          end

          env.response.content_type = "application/json"
          entry.to_json
        end

        post "/v1/keys" do |env|
          body = json_body(env)
          key_name = body["name"]?.try(&.as_s?)
          key_value = body["value"]?.try(&.as_s?)
          key_provider = body["provider"]?.try(&.as_s?)
          key_description = body["description"]?.try(&.as_s?)

          unless key_name && key_value
            env.response.status_code = 400
            next({error: {type: "bad_request", message: "name and value are required"}}.to_json)
          end

          store = key_store
          store[key_name] = {
            "name"        => JSON.parse(key_name.to_json),
            "value"       => JSON.parse(key_value.to_json),
            "provider"    => key_provider ? JSON.parse(key_provider.to_json) : JSON.parse("null"),
            "description" => key_description ? JSON.parse(key_description.to_json) : JSON.parse("null"),
            "created_at"  => JSON.parse(Time.utc.to_rfc3339.to_json),
            "updated_at"  => JSON.parse(Time.utc.to_rfc3339.to_json),
          }
          persist_key_store!(store)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          key_entry(key_name, store[key_name]).to_json
        end

        put "/v1/keys/:keyName" do |env|
          key_name = env.params.url["keyName"]
          body = json_body(env)
          key_value = body["value"]?.try(&.as_s?)
          key_provider = body["provider"]?.try(&.as_s?)
          key_description = body["description"]?.try(&.as_s?)

          store = key_store
          entry = store[key_name]?
          unless entry
            env.response.status_code = 404
            next({error: {type: "not_found", message: "key not found: #{key_name}"}}.to_json)
          end

          entry["value"] = JSON.parse(key_value.to_json) if key_value
          entry["provider"] = key_provider ? JSON.parse(key_provider.to_json) : JSON.parse("null")
          entry["description"] = key_description ? JSON.parse(key_description.to_json) : JSON.parse("null")
          entry["updated_at"] = JSON.parse(Time.utc.to_rfc3339.to_json)
          store[key_name] = entry
          persist_key_store!(store)

          env.response.content_type = "application/json"
          key_entry(key_name, entry).to_json
        end

        delete "/v1/keys/:keyName" do |env|
          key_name = env.params.url["keyName"]
          store = key_store
          unless store.has_key?(key_name)
            env.response.status_code = 404
            next({error: {type: "not_found", message: "key not found: #{key_name}"}}.to_json)
          end

          store.delete(key_name)
          persist_key_store!(store)
          env.response.status_code = 204
          ""
        end
      end

      private def list_keys : Array(Hash(String, JSON::Any))
        key_store.map { |name, entry| key_entry(name, entry) }
      end

      private def get_key(name : String) : Hash(String, JSON::Any)?
        entry = key_store[name]?
        entry ? key_entry(name, entry) : nil
      end

      private def key_entry(name : String, entry : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        {
          "name"        => JSON.parse(name.to_json),
          "provider"    => entry["provider"]? || JSON.parse("null"),
          "description" => entry["description"]? || JSON.parse("null"),
          "created_at"  => entry["created_at"]? || JSON.parse("null"),
          "updated_at"  => entry["updated_at"]? || JSON.parse("null"),
        }
      end

      private def key_store : Hash(String, Hash(String, JSON::Any))
        path = key_store_path
        return {} of String => Hash(String, JSON::Any) unless File.file?(path)

        raw = File.read(path)
        parsed = JSON.parse(raw)
        store = {} of String => Hash(String, JSON::Any)
        parsed.as_h?.try do |h|
          h.each do |k, v|
            store[k] = v.as_h? || {} of String => JSON::Any
          end
        end
        store
      rescue
        {} of String => Hash(String, JSON::Any)
      end

      private def persist_key_store!(store : Hash(String, Hash(String, JSON::Any)))
        path = key_store_path
        Dir.mkdir_p(File.dirname(path))
        File.write(path, store.to_json)
      end

      private def key_store_path : String
        datasets_file_root = begin
          @settings.datasets.file_root
        rescue
          nil
        end
        if file_root = datasets_file_root
          return File.expand_path(File.join(File.dirname(file_root), "..", ".ocawe", "keys.json"))
        end
        File.expand_path(KEY_STORE_PATH)
      end
    end
  end
end
