require "json"
require "uri/params"

module CogniCore
  module Integrations
    module Typesense
      class Service
        getter config : Config

        def initialize(@config : Config, @client : Client = Client.new(@config))
        end

        def ensure_collection! : Nil
          path = "/collections/#{@config.collection}"
          existing = @client.get(path, allow_not_found: true)
          return if existing

          schema = {
            "name" => @config.collection,
            "fields" => [
              {"name" => "id", "type" => "string"},
              {"name" => "title", "type" => "string"},
              {"name" => "text", "type" => "string"},
              {"name" => "tags", "type" => "string[]", "facet" => true, "optional" => true},
              {"name" => "source", "type" => "string", "facet" => true, "optional" => true},
              {"name" => "created_at", "type" => "int64", "optional" => true},
              {"name" => "metadata", "type" => "string", "optional" => true},
              {"name" => "content_type", "type" => "string", "facet" => true, "optional" => true},
              {"name" => "filename", "type" => "string", "facet" => true, "optional" => true},
            ],
            "default_sorting_field" => "created_at",
          }

          @client.post(
            "/collections",
            body: schema.to_json,
            content_type: "application/json",
            allow_conflict: true,
          )
        end

        def search_materials(query : String, per_page : Int32 = 20, filter_by : String? = nil) : Array(Hash(String, JSON::Any))
          params = URI::Params.new
          params["q"] = query.empty? ? "*" : query
          params["query_by"] = "title,text,tags,source,filename"
          params["per_page"] = per_page.to_s
          params["filter_by"] = filter_by.not_nil! if filter_by

          path = "/collections/#{@config.collection}/documents/search?#{params.to_s}"
          payload = @client.get(path) || JSON.parse("{}")
          hits = payload["hits"]?.try(&.as_a?) || [] of JSON::Any

          hits.map do |hit|
            document = hit["document"]?.try(&.as_h?) || {} of String => JSON::Any
            text = document["text"]?.try(&.as_s?) || ""
            title = document["title"]?.try(&.as_s?) || document["filename"]?.try(&.as_s?) || document["id"]?.try(&.as_s?) || ""
            tags = document["tags"]?.try(&.as_a?) || [] of JSON::Any
            score = hit["text_match"]?.try(&.raw) || 0
            snippet = text.size > 500 ? text[0, 500] : text

            {
              "id" => JSON.parse((document["id"]?.try(&.as_s?) || "").to_json),
              "title" => JSON.parse(title.to_json),
              "snippet" => JSON.parse(snippet.to_json),
              "tags" => JSON.parse(tags.map(&.as_s?).to_json),
              "source" => JSON.parse((document["source"]?.try(&.as_s?) || "").to_json),
              "score" => JSON.parse(score.to_json),
            }
          end
        end

        def upsert_materials(items : Array(Hash(String, JSON::Any))) : String
          lines = items.map { |item| normalize_material(item).to_json }.join("\n")
          path = "/collections/#{@config.collection}/documents/import?action=upsert"
          @client.post(path, body: lines, content_type: "text/plain")
        end

        def normalize_material(input : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
          now = Time.utc.to_unix
          id = input["id"]?.try(&.as_s?) || "mat_#{now}_#{Random.rand(100000)}"
          title = input["title"]?.try(&.as_s?) || input["filename"]?.try(&.as_s?) || id
          text = input["text"]?.try(&.as_s?) || ""
          tags = input["tags"]?.try(&.as_a?).try(&.map(&.as_s?)).compact
          source = input["source"]?.try(&.as_s?)
          created_at = input["created_at"]?.try(&.as_i64?) || now
          metadata = input["metadata"]?
          content_type = input["content_type"]?.try(&.as_s?)
          filename = input["filename"]?.try(&.as_s?)

          doc = {
            "id" => JSON.parse(id.to_json),
            "title" => JSON.parse(title.to_json),
            "text" => JSON.parse(text.to_json),
            "created_at" => JSON.parse(created_at.to_json),
          } of String => JSON::Any
          doc["tags"] = JSON.parse(tags.to_json) if tags
          doc["source"] = JSON.parse(source.to_json) if source
          doc["metadata"] = JSON.parse(metadata.to_json) if metadata
          doc["content_type"] = JSON.parse(content_type.to_json) if content_type
          doc["filename"] = JSON.parse(filename.to_json) if filename
          doc
        end
      end
    end
  end
end
