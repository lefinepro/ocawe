module ACD
  module Kemal
    class App
      private def mount_dataset_item_endpoints
        get "/v1/datasets/:datasetId/items" do |env|
          dataset_id = env.params.url["datasetId"]

          response = with_dataset_errors(env) do
            @dataset_service.list_items(dataset_id)
          end
          next response if response.is_a?(String)

          env.response.content_type = "application/json"
          {
            "dataset_id" => dataset_id,
            "items"      => response.as(Array(Ocawe::Dataset::ItemRecord)).map { |item| item_to_json(item) },
          }.to_json
        end

        post "/v1/datasets/:datasetId/items" do |env|
          dataset_id = env.params.url["datasetId"]
          body = json_body(env)

          response = with_dataset_errors(env) do
            @dataset_service.add_items(dataset_id, extract_dataset_items_payload(body))
          end
          next response if response.is_a?(String)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          {
            "dataset_id" => dataset_id,
            "items"      => response.as(Array(Ocawe::Dataset::ItemRecord)).map { |item| item_to_json(item) },
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
          item_to_json(response.as(Ocawe::Dataset::ItemRecord)).to_json
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
            next item_not_found(env, dataset_id, item_id)
          end

          env.response.status_code = 204
          ""
        end
      end

      private def extract_dataset_items_payload(body : Ocawe::Dataset::AnyHash) : Array(Ocawe::Dataset::AnyHash)
        raw_items = [] of Ocawe::Dataset::AnyHash
        if items = body["items"]?.try(&.as_a?)
          items.each do |entry|
            hash = entry.as_h?
            raise "items entries must be objects" unless hash
            raw_items << hash
          end
        elsif item = body["item"]?.try(&.as_h?)
          raw_items << item
        elsif !body.empty?
          raw_items << body
        end

        raise "items payload is required" if raw_items.empty?
        raw_items
      end
    end
  end
end
