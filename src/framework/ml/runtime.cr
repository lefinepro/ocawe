require "./service"
require "./adapters/cogni_ml_adapter"

module Cogni
  module ML
    class Runtime
      def initialize(
        @service : Service,
        @dataset_service : Cogni::Dataset::Service,
        @adapters : Hash(String, Adapter) = default_adapters
      )
      end

      def execute(kind : String, node_id : String, ctx : Cogni::Workflow::NodeContext, config : AnyHash?) : AnyHash
        resolved = config || ({} of String => JSON::Any)
        model_id = resolved["model"]?.try(&.as_s?) || node_id
        model = @service.require_model!(model_id)
        backend = resolve_backend(model, resolved)
        adapter = resolve_adapter(model, resolved)

        result = case kind
                 when "train"
                   train(model, adapter, backend, resolved, ctx)
                 when "embed"
                   embed(model, adapter, backend, resolved, ctx)
                 when "infer"
                   infer(model, adapter, backend, resolved, ctx)
                 when "eval"
                   adapter.eval(model, backend, resolved, ctx)
                 else
                   raise "unsupported ml operation: #{kind}"
                 end
        result["ml_adapter"] = JSON.parse(adapter.id.to_json)
        result["ml_node"] = JSON.parse(node_id.to_json)
        result
      end

      private def train(model : ModelRecord, adapter : Adapter, backend : String, config : AnyHash, ctx : Cogni::Workflow::NodeContext) : AnyHash
        dataset_id = config["dataset"]?.try(&.as_s?) || ctx.input_data["dataset"]?.try(&.as_s?)
        raise "train #{ctx.node_id} requires dataset" unless dataset_id

        dataset = @dataset_service.get_dataset(dataset_id)
        raise "dataset not found: #{dataset_id}" unless dataset
        items = @dataset_service.list_items(dataset_id)
        result = adapter.train(model, backend, dataset_id, items, config, ctx)
        artifact = @service.record_artifact(model.id, "checkpoint", metadata: {
          "dataset_id" => JSON.parse(dataset_id.to_json),
          "backend" => JSON.parse(backend.to_json),
          "sample_count" => JSON.parse(items.size.to_json),
        })
        result["artifact_id"] = JSON.parse(artifact.id.to_json)
        result
      end

      private def embed(model : ModelRecord, adapter : Adapter, backend : String, config : AnyHash, ctx : Cogni::Workflow::NodeContext) : AnyHash
        texts = resolve_texts(config, ctx)
        result = adapter.embed(model, backend, texts, config, ctx)
        if config["persist"]?.try(&.raw) == true
          artifact = @service.record_artifact(model.id, "embedding_index", metadata: {
            "backend" => JSON.parse(backend.to_json),
            "count" => JSON.parse(texts.size.to_json),
          })
          result["artifact_id"] = JSON.parse(artifact.id.to_json)
        end
        result
      end

      private def infer(model : ModelRecord, adapter : Adapter, backend : String, config : AnyHash, ctx : Cogni::Workflow::NodeContext) : AnyHash
        inputs = resolve_texts(config, ctx, input_key: "text", plural_key: "texts")
        adapter.infer(model, backend, inputs, config, ctx)
      end

      private def resolve_texts(
        config : AnyHash,
        ctx : Cogni::Workflow::NodeContext,
        input_key : String = "text",
        plural_key : String = "texts"
      ) : Array(String)
        dataset_id = config["dataset"]?.try(&.as_s?)
        field = config["field"]?.try(&.as_s?) || "text"
        if dataset_id
          return @dataset_service.list_items(dataset_id).compact_map { |item| item.payload[field]?.try(&.as_s?) }
        end

        if values = config[plural_key]?.try(&.as_a?)
          texts = values.compact_map(&.as_s?)
          return texts unless texts.empty?
        end
        if single = config[input_key]?.try(&.as_s?)
          return [single]
        end
        if values = ctx.input_data[plural_key]?.try(&.as_a?)
          texts = values.compact_map(&.as_s?)
          return texts unless texts.empty?
        end
        if single = ctx.input_data[input_key]?.try(&.as_s?)
          return [single]
        end
        if values = ctx.init_data[plural_key]?.try(&.as_a?)
          texts = values.compact_map(&.as_s?)
          return texts unless texts.empty?
        end
        if single = ctx.init_data[input_key]?.try(&.as_s?)
          return [single]
        end
        if values = ctx.state[plural_key]?.try(&.as_a?)
          texts = values.compact_map(&.as_s?)
          return texts unless texts.empty?
        end
        if single = ctx.state[input_key]?.try(&.as_s?)
          return [single]
        end

        raise "#{ctx.node_id} requires text/texts or dataset"
      end

      private def resolve_backend(model : ModelRecord, config : AnyHash) : String
        requested = config["backend"]?.try(&.as_s?).try(&.strip.downcase)
        return requested unless requested.nil? || requested.empty?
        model.backends.first? || @service.backend_priority.first? || "cuda"
      end

      private def resolve_adapter(model : ModelRecord, config : AnyHash) : Adapter
        name = config["adapter"]?.try(&.as_s?) || model.adapter
        @adapters[name]? || raise "unsupported ml adapter: #{name}"
      end

      private def default_adapters : Hash(String, Adapter)
        adapter = Adapters::CogniMlAdapter.new
        adapters = {} of String => Adapter
        adapters[adapter.id] = adapter
        adapters
      end
    end
  end
end
