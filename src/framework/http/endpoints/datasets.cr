module ACD
  module HTTP
    class App
      private def mount_dataset_endpoints
        get "/v1/datasets" do |env|
          datasets = @dataset_service.list_datasets

          env.response.content_type = "application/json"
          {
            "datasets" => datasets.map { |dataset| dataset_to_json(dataset) },
          }.to_json
        end

        post "/v1/datasets" do |env|
          body = json_body(env)
          id = body["id"]?.try(&.as_s?) || body["name"]?.try(&.as_s?) || ""
          description = body["description"]?.try(&.as_s?)
          schema_source = body["schema"]?.try(&.as_s?)

          response = with_dataset_errors(env) do
            @dataset_service.create_dataset(id, description: description, schema_source: schema_source)
          end
          next response if response.is_a?(String)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          dataset_to_json(response.as(Cogni::Dataset::DatasetRecord)).to_json
        end

        get "/v1/datasets/:datasetId" do |env|
          dataset_id = env.params.url["datasetId"]
          dataset = @dataset_service.get_dataset(dataset_id)

          unless dataset
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({"error" => {"type" => "not_found", "message" => "dataset not found: #{dataset_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          dataset_to_json(dataset.not_nil!).to_json
        end

        patch "/v1/datasets/:datasetId" do |env|
          dataset_id = env.params.url["datasetId"]
          body = json_body(env)

          description = body["description"]?.try(&.as_s?)
          schema_source = body["schema"]?.try(&.as_s?)

          response = with_dataset_errors(env) do
            @dataset_service.update_dataset(dataset_id, description: description, schema_source: schema_source)
          end
          next response if response.is_a?(String)

          env.response.content_type = "application/json"
          dataset_to_json(response.as(Cogni::Dataset::DatasetRecord)).to_json
        end

        delete "/v1/datasets/:datasetId" do |env|
          dataset_id = env.params.url["datasetId"]

          response = with_dataset_errors(env) do
            @dataset_service.delete_dataset(dataset_id)
          end
          next response if response.is_a?(String)

          deleted = response.as(Bool)
          unless deleted
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({"error" => {"type" => "not_found", "message" => "dataset not found: #{dataset_id}"}}.to_json)
          end

          env.response.status_code = 204
          ""
        end

        get "/v1/datasets/:datasetId/items" do |env|
          dataset_id = env.params.url["datasetId"]

          response = with_dataset_errors(env) do
            @dataset_service.list_items(dataset_id)
          end
          next response if response.is_a?(String)

          env.response.content_type = "application/json"
          {
            "dataset_id" => dataset_id,
            "items" => response.as(Array(Cogni::Dataset::ItemRecord)).map { |item| item_to_json(item) },
          }.to_json
        end

        post "/v1/datasets/:datasetId/items" do |env|
          dataset_id = env.params.url["datasetId"]
          body = json_body(env)

          response = with_dataset_errors(env) do
            raw_items = [] of Cogni::Dataset::AnyHash
            if items = body["items"]?.try(&.as_a?)
              items.each do |entry|
                hash = entry.as_h?
                raise "items entries must be objects" unless hash
                raw_items << hash
              end
            elsif item = body["item"]?.try(&.as_h?)
              raw_items << item
            else
              hash = body.as_h?
              if hash && !hash.empty?
                raw_items << hash
              end
            end

            raise "items payload is required" if raw_items.empty?
            @dataset_service.add_items(dataset_id, raw_items)
          end
          next response if response.is_a?(String)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          {
            "dataset_id" => dataset_id,
            "items" => response.as(Array(Cogni::Dataset::ItemRecord)).map { |item| item_to_json(item) },
          }.to_json
        end

        patch "/v1/datasets/:datasetId/items/:itemId" do |env|
          dataset_id = env.params.url["datasetId"]
          item_id = env.params.url["itemId"]
          body = json_body(env)

          payload = body["payload"]?.try(&.as_h?) || body

          response = with_dataset_errors(env) do
            @dataset_service.update_item(dataset_id, item_id, payload)
          end
          next response if response.is_a?(String)

          env.response.content_type = "application/json"
          item_to_json(response.as(Cogni::Dataset::ItemRecord)).to_json
        end

        delete "/v1/datasets/:datasetId/items/:itemId" do |env|
          dataset_id = env.params.url["datasetId"]
          item_id = env.params.url["itemId"]

          response = with_dataset_errors(env) do
            @dataset_service.delete_item(dataset_id, item_id)
          end
          next response if response.is_a?(String)

          deleted = response.as(Bool)
          unless deleted
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({"error" => {"type" => "not_found", "message" => "item not found: #{dataset_id}/#{item_id}"}}.to_json)
          end

          env.response.status_code = 204
          ""
        end
      end

      private def with_dataset_errors(env, &block : -> T) : (T | String) forall T
        block.call
      rescue ex
        message = ex.message || "dataset request failed"

        if message.includes?("not found")
          env.response.status_code = 404
          env.response.content_type = "application/json"
          return {"error" => {"type" => "not_found", "message" => message}}.to_json
        end

        if message.includes?("required") || message.includes?("invalid") || message.includes?("validation")
          env.response.status_code = 400
          env.response.content_type = "application/json"
          return {"error" => {"type" => "bad_request", "message" => message}}.to_json
        end

        if message.includes?("already exists") || message.includes?("duplicate")
          env.response.status_code = 409
          env.response.content_type = "application/json"
          return {"error" => {"type" => "conflict", "message" => message}}.to_json
        end

        env.response.status_code = 422
        env.response.content_type = "application/json"
        {"error" => {"type" => "dataset_error", "message" => message}}.to_json
      end

      private def dataset_to_json(dataset : Cogni::Dataset::DatasetRecord) : Hash(String, JSON::Any)
        {
          "id" => JSON.parse(dataset.id.to_json),
          "description" => JSON.parse(dataset.description.to_json),
          "schema" => JSON.parse(dataset.schema_source.to_json),
          "source" => JSON.parse(dataset.source.to_json),
          "created_at" => JSON.parse(dataset.created_at.to_json),
          "updated_at" => JSON.parse(dataset.updated_at.to_json),
        }
      end

      private def item_to_json(item : Cogni::Dataset::ItemRecord) : Hash(String, JSON::Any)
        {
          "id" => JSON.parse(item.id.to_json),
          "payload" => JSON.parse(item.payload.to_json),
          "created_at" => JSON.parse(item.created_at.to_json),
          "updated_at" => JSON.parse(item.updated_at.to_json),
        }
      end
    end
  end
end
