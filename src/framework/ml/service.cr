require "uuid"
require "./store"

module Cogni
  module ML
    class Service
      getter store : Store::Base
      getter default_adapter : String
      getter backend_priority : Array(String)

      def initialize(
        @store : Store::Base = Store::InMemory.new,
        @default_adapter : String = "cogni_ml",
        @backend_priority : Array(String) = ["cuda", "amd", "metal"] of String
      )
        @lock = Mutex.new
        @dsl_sources = {} of String => String
      end

      def reset_dsl_sources! : Nil
        @lock.synchronize { @dsl_sources.clear }
      end

      def register_from_dsl(
        id : String,
        source_file : String,
        description : String? = nil,
        task : String? = nil,
        base_model : String? = nil,
        runtime : AnyHash? = nil,
        metadata : AnyHash? = nil
      ) : ModelRecord
        model_id = normalize_id(id)

        @lock.synchronize do
          previous_source = @dsl_sources[model_id]?
          if previous_source && previous_source != source_file
            raise "model '#{model_id}' declared in multiple workflows: #{previous_source} and #{source_file}"
          end
          @dsl_sources[model_id] = source_file
        end

        existing = @store.get_model(model_id)
        source = runtime.try { |cfg| cfg["source"]?.try(&.as_s?) }
        adapter = runtime.try { |cfg| cfg["adapter"]?.try(&.as_s?) } || existing.try(&.adapter) || @default_adapter
        backends = normalize_backends(runtime, existing)
        merged_metadata = merge_metadata(existing.try(&.metadata), metadata)

        record = ModelRecord.new(
          id: model_id,
          description: description || existing.try(&.description),
          task: task || existing.try(&.task),
          base_model: base_model || existing.try(&.base_model),
          adapter: adapter,
          source: source || existing.try(&.source),
          backends: backends,
          metadata: merged_metadata,
          declared_from: source_file,
          created_at: existing.try(&.created_at) || Time.utc.to_s,
          updated_at: Time.utc.to_s,
        )
        @store.upsert_model(record)
      end

      def list_models : Array(ModelRecord)
        @store.list_models.sort_by(&.id)
      end

      def get_model(id : String) : ModelRecord?
        @store.get_model(normalize_id(id))
      end

      def require_model!(id : String) : ModelRecord
        get_model(id) || raise "model not found: #{normalize_id(id)}"
      end

      def record_artifact(
        model_id : String,
        kind : String,
        status : String = "ready",
        metadata : AnyHash = {} of String => JSON::Any
      ) : ArtifactRecord
        model = require_model!(model_id)
        now = Time.utc.to_s
        artifact = ArtifactRecord.new(
          id: "artifact_#{UUID.random}",
          model_id: model.id,
          kind: kind.strip.empty? ? "artifact" : kind.strip,
          status: status.strip.empty? ? "ready" : status.strip,
          metadata: metadata,
          created_at: now,
          updated_at: now,
        )
        @store.add_artifact(artifact)
      end

      def list_artifacts(model_id : String? = nil) : Array(ArtifactRecord)
        normalized = model_id.try { |value| normalize_id(value) }
        @store.list_artifacts(normalized).sort_by(&.created_at)
      end

      private def normalize_id(raw : String) : String
        normalized = raw.strip
        raise "model id is required" if normalized.empty?
        normalized
      end

      private def normalize_backends(runtime : AnyHash?, existing : ModelRecord?) : Array(String)
        raw = runtime.try { |cfg| cfg["backends"]?.try(&.as_a?) }
        parsed = raw.try { |entries| entries.compact_map(&.as_s?) } || [] of String
        values = parsed.map(&.strip.downcase).reject(&.empty?).uniq
        return values unless values.empty?
        previous = existing.try(&.backends) || [] of String
        return previous unless previous.empty?
        @backend_priority.dup
      end

      private def merge_metadata(left : AnyHash?, right : AnyHash?) : AnyHash?
        return right unless left
        return left unless right
        merged = left.dup
        right.each { |key, value| merged[key] = value }
        merged
      end
    end
  end
end
