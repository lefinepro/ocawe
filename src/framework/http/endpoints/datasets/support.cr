module ACD
  module Kemal
    class App
      private def dataset_not_found(env, dataset_id : String) : String
        json_error(env, 404, "not_found", "dataset not found: #{dataset_id}")
      end

      private def item_not_found(env, dataset_id : String, item_id : String) : String
        json_error(env, 404, "not_found", "item not found: #{dataset_id}/#{item_id}")
      end

      private def with_dataset_errors(env, &block : -> T) : (T | String) forall T
        block.call
      rescue ex
        message = ex.message || "dataset request failed"

        if message.includes?("not found")
          return json_error(env, 404, "not_found", message)
        end

        if message.includes?("required") || message.includes?("invalid") || message.includes?("validation")
          return json_error(env, 400, "bad_request", message)
        end

        if message.includes?("already exists") || message.includes?("duplicate")
          return json_error(env, 409, "conflict", message)
        end

        json_error(env, 422, "dataset_error", message)
      end

      private def dataset_to_json(dataset : Cogni::Dataset::DatasetRecord) : Hash(String, JSON::Any)
        {
          "id"                 => JSON.parse(dataset.id.to_json),
          "description"        => JSON.parse(dataset.description.to_json),
          "schema"             => JSON.parse(dataset.schema_source.to_json),
          "schema_description" => JSON.parse(dataset.schema_description.to_json),
          "source"             => JSON.parse(dataset.source.to_json),
          "source_path"        => JSON.parse(dataset.source_path.to_json),
          "source_format"      => JSON.parse(dataset.source_format.to_json),
          "source_options"     => JSON.parse(dataset.source_options.to_json),
          "created_at"         => JSON.parse(dataset.created_at.to_json),
          "updated_at"         => JSON.parse(dataset.updated_at.to_json),
        }
      end

      private def item_to_json(item : Cogni::Dataset::ItemRecord) : Hash(String, JSON::Any)
        {
          "id"         => JSON.parse(item.id.to_json),
          "payload"    => JSON.parse(item.payload.to_json),
          "created_at" => JSON.parse(item.created_at.to_json),
          "updated_at" => JSON.parse(item.updated_at.to_json),
        }
      end
    end
  end
end
