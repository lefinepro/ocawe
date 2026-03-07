module ACD
  module Kemal
    class App
      private def local_domain_from_actor_url(actor : String) : String
        uri = URI.parse(actor)
        host = uri.host.to_s
        host = "127.0.0.1" if host.empty?
        port = uri.port
        if port
          "#{uri.scheme || "http"}://#{host}:#{port}"
        else
          "#{uri.scheme || "http"}://#{host}"
        end
      rescue
        "http://127.0.0.1:4111"
      end

      private def extract_activities_from_outbox(outbox_doc : Hash(String, JSON::Any)) : Array(Hash(String, JSON::Any))
        items = [] of Hash(String, JSON::Any)
        ordered_items = outbox_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
        if ordered_items.empty?
          if first = outbox_doc["first"]?
            first_doc = if first_hash = first.as_h?
                          first_hash
                        elsif first_url = first.as_s?
                          fetch_jsonld_activity(first_url)
                        else
                          {} of String => JSON::Any
                        end
            ordered_items = first_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
          end
        end
        ordered_items.each do |entry|
          hash = entry.as_h?
          items << hash if hash
        end
        items
      end

      private def resolve_activity_object_id(activity : Hash(String, JSON::Any)) : String
        object = activity["object"]?
        if object_string = object.try(&.as_s?)
          return object_string
        end
        object_hash = object.try(&.as_h?) || {} of String => JSON::Any
        object_hash["id"]?.try(&.as_s?).to_s
      end

      private def local_domain_from_request(env) : String
        host = env.request.headers["Host"]?.to_s
        host = "127.0.0.1:4111" if host.nil? || host.empty?
        "http://#{host}"
      end
    end
  end
end
