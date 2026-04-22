require "json"

module Cogni
  module Dataset
    alias AnyHash = Hash(String, JSON::Any)

    struct DatasetRecord
      include JSON::Serializable

      getter id : String
      getter description : String?
      getter schema_description : String?
      getter schema_source : String?
      getter source : String?
      getter source_path : String?
      getter source_format : String?
      getter source_options : AnyHash?
      getter created_at : String
      getter updated_at : String

      def initialize(
        @id : String,
        @description : String? = nil,
        @schema_description : String? = nil,
        @schema_source : String? = nil,
        @source : String? = nil,
        @source_path : String? = nil,
        @source_format : String? = nil,
        @source_options : AnyHash? = nil,
        @created_at : String = Time.utc.to_s,
        @updated_at : String = Time.utc.to_s
      )
      end
    end

    struct ItemRecord
      include JSON::Serializable

      getter id : String
      getter payload : AnyHash
      getter created_at : String
      getter updated_at : String

      def initialize(
        @id : String,
        @payload : AnyHash,
        @created_at : String = Time.utc.to_s,
        @updated_at : String = Time.utc.to_s
      )
      end
    end

    module Store
      abstract class Base
        abstract def list_datasets : Array(DatasetRecord)
        abstract def get_dataset(id : String) : DatasetRecord?
        abstract def upsert_dataset(dataset : DatasetRecord) : DatasetRecord
        abstract def delete_dataset(id : String) : Bool

        abstract def list_items(dataset_id : String) : Array(ItemRecord)
        abstract def add_items(dataset_id : String, items : Array(ItemRecord)) : Array(ItemRecord)
        abstract def update_item(dataset_id : String, item_id : String, payload : AnyHash) : ItemRecord?
        abstract def delete_item(dataset_id : String, item_id : String) : Bool
      end

      class InMemory < Base
        def initialize
          @datasets = {} of String => DatasetRecord
          @items = {} of String => Hash(String, ItemRecord)
          @lock = Mutex.new
        end

        def list_datasets : Array(DatasetRecord)
          @lock.synchronize { @datasets.values.to_a }
        end

        def get_dataset(id : String) : DatasetRecord?
          @lock.synchronize { @datasets[id]? }
        end

        def upsert_dataset(dataset : DatasetRecord) : DatasetRecord
          @lock.synchronize do
            @datasets[dataset.id] = dataset
            @items[dataset.id] ||= {} of String => ItemRecord
          end
          dataset
        end

        def delete_dataset(id : String) : Bool
          @lock.synchronize do
            removed = @datasets.delete(id)
            @items.delete(id)
            !removed.nil?
          end
        end

        def list_items(dataset_id : String) : Array(ItemRecord)
          @lock.synchronize do
            (@items[dataset_id]? || ({} of String => ItemRecord)).values.to_a
          end
        end

        def add_items(dataset_id : String, items : Array(ItemRecord)) : Array(ItemRecord)
          @lock.synchronize do
            bucket = @items[dataset_id]? || begin
              created = {} of String => ItemRecord
              @items[dataset_id] = created
              created
            end
            items.each { |item| bucket[item.id] = item }
          end
          items
        end

        def update_item(dataset_id : String, item_id : String, payload : AnyHash) : ItemRecord?
          @lock.synchronize do
            bucket = @items[dataset_id]?
            return nil unless bucket

            current = bucket[item_id]?
            return nil unless current

            updated = ItemRecord.new(
              id: current.id,
              payload: payload,
              created_at: current.created_at,
              updated_at: Time.utc.to_s,
            )
            bucket[item_id] = updated
            updated
          end
        end

        def delete_item(dataset_id : String, item_id : String) : Bool
          @lock.synchronize do
            bucket = @items[dataset_id]?
            return false unless bucket
            !bucket.delete(item_id).nil?
          end
        end
      end

      class File < Base
        struct Snapshot
          include JSON::Serializable

          getter datasets : Array(DatasetRecord)
          getter items : Hash(String, Array(ItemRecord))

          def initialize(
            @datasets : Array(DatasetRecord) = [] of DatasetRecord,
            @items : Hash(String, Array(ItemRecord)) = {} of String => Array(ItemRecord)
          )
          end
        end

        def initialize(@root : String)
          @lock = Mutex.new
          Dir.mkdir_p(@root)
          @path = ::File.join(@root, "datasets.json")
        end

        def list_datasets : Array(DatasetRecord)
          @lock.synchronize { snapshot.datasets }
        end

        def get_dataset(id : String) : DatasetRecord?
          @lock.synchronize { snapshot.datasets.find { |dataset| dataset.id == id } }
        end

        def upsert_dataset(dataset : DatasetRecord) : DatasetRecord
          @lock.synchronize do
            snap = snapshot
            datasets = snap.datasets.dup
            idx = datasets.index { |entry| entry.id == dataset.id }
            if idx
              datasets[idx] = dataset
            else
              datasets << dataset
            end

            items = snap.items.dup
            items[dataset.id] ||= [] of ItemRecord
            persist(Snapshot.new(datasets: datasets, items: items))
          end
          dataset
        end

        def delete_dataset(id : String) : Bool
          @lock.synchronize do
            snap = snapshot
            datasets = snap.datasets.reject { |dataset| dataset.id == id }
            return false if datasets.size == snap.datasets.size

            items = snap.items.dup
            items.delete(id)
            persist(Snapshot.new(datasets: datasets, items: items))
            true
          end
        end

        def list_items(dataset_id : String) : Array(ItemRecord)
          @lock.synchronize { (snapshot.items[dataset_id]? || [] of ItemRecord).dup }
        end

        def add_items(dataset_id : String, items : Array(ItemRecord)) : Array(ItemRecord)
          @lock.synchronize do
            snap = snapshot
            bucket = (snap.items[dataset_id]? || [] of ItemRecord).dup
            by_id = {} of String => ItemRecord
            bucket.each { |item| by_id[item.id] = item }
            items.each { |item| by_id[item.id] = item }

            updated_items = snap.items.dup
            updated_items[dataset_id] = by_id.values.to_a
            persist(Snapshot.new(datasets: snap.datasets.dup, items: updated_items))
          end
          items
        end

        def update_item(dataset_id : String, item_id : String, payload : AnyHash) : ItemRecord?
          @lock.synchronize do
            snap = snapshot
            bucket = (snap.items[dataset_id]? || [] of ItemRecord).dup
            idx = bucket.index { |item| item.id == item_id }
            return nil unless idx

            current = bucket[idx]
            updated = ItemRecord.new(
              id: current.id,
              payload: payload,
              created_at: current.created_at,
              updated_at: Time.utc.to_s,
            )
            bucket[idx] = updated

            updated_items = snap.items.dup
            updated_items[dataset_id] = bucket
            persist(Snapshot.new(datasets: snap.datasets.dup, items: updated_items))
            updated
          end
        end

        def delete_item(dataset_id : String, item_id : String) : Bool
          @lock.synchronize do
            snap = snapshot
            bucket = (snap.items[dataset_id]? || [] of ItemRecord).dup
            next_size = bucket.reject { |item| item.id == item_id }
            return false if next_size.size == bucket.size

            updated_items = snap.items.dup
            updated_items[dataset_id] = next_size
            persist(Snapshot.new(datasets: snap.datasets.dup, items: updated_items))
            true
          end
        end

        private def snapshot : Snapshot
          return Snapshot.new unless ::File.exists?(@path)

          Snapshot.from_json(::File.read(@path))
        rescue
          Snapshot.new
        end

        private def persist(snapshot : Snapshot)
          ::File.write(@path, snapshot.to_json)
        end
      end
    end
  end
end
