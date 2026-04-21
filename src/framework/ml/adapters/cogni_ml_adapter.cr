require "digest/sha256"
require "../adapter"

module Cogni
  module ML
    module Adapters
      # Compatibility adapter shaped for later direct wiring to skuznetsov/cogni-ml.
      class CogniMlAdapter < Adapter
        def initialize
          super("cogni_ml")
        end

        def train(
          model : ModelRecord,
          backend : String,
          dataset_id : String,
          items : Array(Cogni::Dataset::ItemRecord),
          config : AnyHash,
          ctx : Cogni::Workflow::NodeContext
        ) : AnyHash
          epochs = config["epochs"]?.try(&.as_i?) || 1
          batch_size = config["batch_size"]?.try(&.as_i?) || items.size.clamp(1, 64)
          loss = items.empty? ? 0.0 : 1.0 / items.size
          {
            "ml_operation" => JSON.parse("train".to_json),
            "ml_model" => JSON.parse(model.id.to_json),
            "ml_backend" => JSON.parse(backend.to_json),
            "dataset_id" => JSON.parse(dataset_id.to_json),
            "epochs" => JSON.parse(epochs.to_json),
            "batch_size" => JSON.parse(batch_size.to_json),
            "samples_seen" => JSON.parse(items.size.to_json),
            "training_loss" => JSON.parse(loss.to_json),
            "run_id" => JSON.parse(ctx.run_id.to_json),
          }
        end

        def embed(
          model : ModelRecord,
          backend : String,
          texts : Array(String),
          config : AnyHash,
          ctx : Cogni::Workflow::NodeContext
        ) : AnyHash
          dims = (config["dimensions"]?.try(&.as_i?) || 8).clamp(2, 64)
          vectors = texts.map { |text| embedding_for(text, dims) }
          {
            "ml_operation" => JSON.parse("embed".to_json),
            "ml_model" => JSON.parse(model.id.to_json),
            "ml_backend" => JSON.parse(backend.to_json),
            "embedding_dimensions" => JSON.parse(dims.to_json),
            "embedding_count" => JSON.parse(vectors.size.to_json),
            "embeddings" => JSON.parse(vectors.to_json),
            "texts" => JSON.parse(texts.to_json),
            "run_id" => JSON.parse(ctx.run_id.to_json),
          }
        end

        def infer(
          model : ModelRecord,
          backend : String,
          inputs : Array(String),
          config : AnyHash,
          ctx : Cogni::Workflow::NodeContext
        ) : AnyHash
          labels = config["labels"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || ["positive", "negative"] of String
          predictions = inputs.map do |input|
            idx = byte_sum(input) % labels.size
            score = ((byte_sum("#{model.id}:#{input}") % 100) + 1).to_f / 100.0
            {
              "input" => input,
              "label" => labels[idx],
              "score" => score,
            }
          end
          {
            "ml_operation" => JSON.parse("infer".to_json),
            "ml_model" => JSON.parse(model.id.to_json),
            "ml_backend" => JSON.parse(backend.to_json),
            "prediction_count" => JSON.parse(predictions.size.to_json),
            "predictions" => JSON.parse(predictions.to_json),
            "run_id" => JSON.parse(ctx.run_id.to_json),
          }
        end

        def eval(
          model : ModelRecord,
          backend : String,
          config : AnyHash,
          ctx : Cogni::Workflow::NodeContext
        ) : AnyHash
          predicted = config["predictions"]?.try(&.as_a?) || ctx.state["predictions"]?.try(&.as_a?) || [] of JSON::Any
          expected = config["expected"]?.try(&.as_a?) || ctx.input_data["expected"]?.try(&.as_a?) || [] of JSON::Any
          accuracy = compute_accuracy(predicted, expected)
          {
            "ml_operation" => JSON.parse("eval".to_json),
            "ml_model" => JSON.parse(model.id.to_json),
            "ml_backend" => JSON.parse(backend.to_json),
            "evaluation_samples" => JSON.parse(expected.size.to_json),
            "accuracy" => JSON.parse(accuracy.to_json),
            "run_id" => JSON.parse(ctx.run_id.to_json),
          }
        end

        private def embedding_for(text : String, dims : Int32) : Array(Float64)
          digest = Digest::SHA256.digest(text)
          (0...dims).map do |idx|
            byte = digest[idx % digest.size].to_i
            ((byte % 200) - 100).to_f / 100.0
          end
        end

        private def byte_sum(text : String) : Int32
          total = 0
          text.each_byte do |byte|
            total += byte.to_i
          end
          total
        end

        private def compute_accuracy(predicted : Array(JSON::Any), expected : Array(JSON::Any)) : Float64
          return 0.0 if predicted.empty? || expected.empty?
          total = {predicted.size, expected.size}.min
          return 0.0 if total == 0

          hits = 0
          total.times do |idx|
            predicted_hash = predicted[idx].as_h?
            predicted_label = predicted_hash.try { |hash| hash["label"]?.try(&.as_s?) } || predicted[idx].as_s?
            expected_label = expected[idx].as_s?
            hits += 1 if predicted_label && expected_label && predicted_label == expected_label
          end
          hits.to_f / total.to_f
        end
      end
    end
  end
end
