require "json"
require "set"
require "uuid"
require "../workflows/dsl/crystal_dsl"
require "./importer"
require "./store"

module Cogni
  module Dataset
    class Service
      getter store : Store::Base

      def initialize(@store : Store::Base = Store::InMemory.new)
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
        schema_description : String? = nil,
        schema_source : String? = nil,
        seed_items : Array(AnyHash) = [] of AnyHash,
        source_path : String? = nil,
        source_format : String? = nil,
        source_options : AnyHash? = nil,
        base_dir : String? = nil
      ) : DatasetRecord
        dataset_id = normalize_dataset_id(id)

        @lock.synchronize do
          previous_source = @dsl_sources[dataset_id]?
          if previous_source && previous_source != source_file
            raise "dataset '#{dataset_id}' declared in multiple workflows: #{previous_source} and #{source_file}"
          end
          @dsl_sources[dataset_id] = source_file
        end

        existing = @store.get_dataset(dataset_id)
        imported_items = [] of AnyHash
        if path = source_path
          imported_items = Importer.load(path, source_format, base_dir, source_options)
        end
        all_seed_items = seed_items + imported_items
        if existing
          updated = DatasetRecord.new(
            id: existing.id,
            description: description || existing.description,
            schema_description: schema_description || existing.schema_description,
            schema_source: schema_source || existing.schema_source,
            source: "dsl",
            source_path: source_path || existing.source_path,
            source_format: normalize_source_format(source_format || existing.source_format),
            source_options: source_options || existing.source_options,
            created_at: existing.created_at,
            updated_at: Time.utc.to_s,
          )
          @store.upsert_dataset(updated)
          return updated
        end

        compile_schema(schema_source, dataset_id)

        created = DatasetRecord.new(
          id: dataset_id,
          description: description,
          schema_description: schema_description,
          schema_source: schema_source,
          source: "dsl",
          source_path: source_path,
          source_format: normalize_source_format(source_format),
          source_options: source_options,
          created_at: Time.utc.to_s,
          updated_at: Time.utc.to_s,
        )
        @store.upsert_dataset(created)

        unless all_seed_items.empty?
          normalized = normalize_items(all_seed_items, dataset_id, schema_source)
          @store.add_items(dataset_id, normalized)
        end

        created
      end

      def list_datasets : Array(DatasetRecord)
        @store.list_datasets.sort_by(&.id)
      end

      def get_dataset(id : String) : DatasetRecord?
        @store.get_dataset(normalize_dataset_id(id))
      end

      def create_dataset(
        id : String,
        description : String? = nil,
        schema_description : String? = nil,
        schema_source : String? = nil,
        source_path : String? = nil,
        source_format : String? = nil,
        source_options : AnyHash? = nil,
        base_dir : String? = nil
      ) : DatasetRecord
        dataset_id = normalize_dataset_id(id)
        raise "dataset already exists: #{dataset_id}" if @store.get_dataset(dataset_id)

        compile_schema(schema_source, dataset_id)
        created = DatasetRecord.new(
          id: dataset_id,
          description: description,
          schema_description: schema_description,
          schema_source: schema_source,
          source: "api",
          source_path: source_path,
          source_format: normalize_source_format(source_format),
          source_options: source_options,
          created_at: Time.utc.to_s,
          updated_at: Time.utc.to_s,
        )
        @store.upsert_dataset(created)

        if source_path
          imported = Importer.load(source_path, source_format, base_dir, source_options)
          @store.add_items(dataset_id, normalize_items(imported, dataset_id, schema_source))
        end

        created
      end

      def update_dataset(
        id : String,
        description : String?,
        schema_description : String?,
        schema_source : String?,
        source_path : String? = nil,
        source_format : String? = nil,
        source_options : AnyHash? = nil
      ) : DatasetRecord
        dataset_id = normalize_dataset_id(id)
        current = @store.get_dataset(dataset_id)
        raise "dataset not found: #{dataset_id}" unless current
        current = current.not_nil!

        next_description = description.nil? ? current.description : description
        next_schema = schema_source.nil? ? current.schema_source : schema_source
        compile_schema(next_schema, dataset_id)

        updated = DatasetRecord.new(
          id: current.id,
          description: next_description,
          schema_description: schema_description.nil? ? current.schema_description : schema_description,
          schema_source: next_schema,
          source: current.source,
          source_path: source_path.nil? ? current.source_path : source_path,
          source_format: normalize_source_format(source_format.nil? ? current.source_format : source_format),
          source_options: source_options || current.source_options,
          created_at: current.created_at,
          updated_at: Time.utc.to_s,
        )
        @store.upsert_dataset(updated)
      end

      def delete_dataset(id : String) : Bool
        dataset_id = normalize_dataset_id(id)
        @store.delete_dataset(dataset_id)
      end

      def list_items(dataset_id : String) : Array(ItemRecord)
        dataset = require_dataset!(dataset_id)
        _ = dataset
        @store.list_items(normalize_dataset_id(dataset_id)).sort_by(&.id)
      end

      def add_items(dataset_id : String, raw_items : Array(AnyHash)) : Array(ItemRecord)
        dataset = require_dataset!(dataset_id)
        normalized = normalize_items(raw_items, dataset.id, dataset.schema_source)
        existing_ids = @store.list_items(dataset.id).map(&.id).to_set

        normalized.each do |item|
          raise "item already exists: #{dataset.id}/#{item.id}" if existing_ids.includes?(item.id)
          existing_ids << item.id
        end

        @store.add_items(dataset.id, normalized)
      end

      def update_item(dataset_id : String, item_id : String, payload : AnyHash) : ItemRecord
        dataset = require_dataset!(dataset_id)
        normalized_payload = normalize_payload(payload)
        validate_payload!(dataset.schema_source, dataset.id, normalized_payload)

        updated = @store.update_item(dataset.id, item_id, normalized_payload)
        raise "item not found: #{dataset.id}/#{item_id}" unless updated
        updated.not_nil!
      end

      def delete_item(dataset_id : String, item_id : String) : Bool
        dataset = require_dataset!(dataset_id)
        @store.delete_item(dataset.id, item_id)
      end

      private def require_dataset!(dataset_id : String) : DatasetRecord
        normalized = normalize_dataset_id(dataset_id)
        @store.get_dataset(normalized) || raise "dataset not found: #{normalized}"
      end

      private def normalize_dataset_id(raw : String) : String
        normalized = raw.strip
        raise "dataset id is required" if normalized.empty?
        normalized
      end

      private def normalize_source_format(value : String?) : String?
        normalized = value.to_s.strip.downcase
        normalized.empty? ? nil : normalized
      end

      private def normalize_items(raw_items : Array(AnyHash), dataset_id : String, schema_source : String?) : Array(ItemRecord)
        now = Time.utc.to_s
        generated_ids = Set(String).new
        normalized = [] of ItemRecord

        raw_items.each do |item|
          id, payload = extract_item_parts(item)
          item_id = id || generated_item_id
          raise "duplicate item id in payload: #{item_id}" if generated_ids.includes?(item_id)
          generated_ids << item_id

          validate_payload!(schema_source, dataset_id, payload)
          normalized << ItemRecord.new(id: item_id, payload: payload, created_at: now, updated_at: now)
        end

        normalized
      end

      private def extract_item_parts(item : AnyHash) : Tuple(String?, AnyHash)
        id = item["id"]?.try(&.as_s?)
        payload = normalize_payload(item)
        payload.delete("id")
        {id, payload}
      end

      private def normalize_payload(value : AnyHash) : AnyHash
        normalized = {} of String => JSON::Any
        value.each { |k, v| normalized[k] = v }
        normalized
      end

      private def generated_item_id : String
        "item_#{UUID.random.to_s}"
      end

      private def compile_schema(schema_source : String?, dataset_id : String)
        return unless schema_source
        stripped = schema_source.strip
        return if stripped.empty?
        Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "dataset #{dataset_id} schema")
      rescue ex
        raise "dataset #{dataset_id} schema is invalid: #{ex.message}"
      end

      private def validate_payload!(schema_source : String?, dataset_id : String, payload : AnyHash) : Nil
        return unless schema_source
        stripped = schema_source.strip
        return if stripped.empty?

        validator = Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "dataset #{dataset_id} schema")
        validator.validate(JSON.parse(payload.to_json), "$.item")
      rescue ex : Cogni::Workflows::DSL::ValidationError
        raise "dataset #{dataset_id} item validation failed: #{ex.message}"
      rescue ex : Cogni::Workflows::DSL::CrystalDSL::ParseError
        raise "dataset #{dataset_id} schema is invalid: #{ex.message}"
      end
    end
  end
end
