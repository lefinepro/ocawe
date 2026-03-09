module ACD
  module Kemal
    class App
      private def mount_dataset_catalog_endpoints
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
            next dataset_not_found(env, dataset_id)
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
            next dataset_not_found(env, dataset_id)
          end

          env.response.status_code = 204
          ""
        end
      end
    end
  end
end
