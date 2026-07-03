require "db"
require "json"
require "sqlite3"

module Ocawe
  module Dataset
    alias AnyHash = Hash(String, JSON::Any)

    struct DatasetRecord
      include JSON::Serializable

      getter id : String
      getter description : String?
      getter schema_source : String?
      getter source : String?
      getter created_at : String
      getter updated_at : String

      def initialize(
        @id : String,
        @description : String? = nil,
        @schema_source : String? = nil,
        @source : String? = nil,
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

      class SQLite < Base
        @path : String
        @db : DB::Database

        def initialize(path : String)
          @lock = Mutex.new
          @path = normalize_path(path)
          dir = ::File.dirname(@path)
          Dir.mkdir_p(dir) unless Dir.exists?(dir)
          @db = DB.open("sqlite3://#{@path}")
          migrate!
        end

        def list_datasets : Array(DatasetRecord)
          @lock.synchronize do
            records = [] of DatasetRecord
            @db.query_each(
              "SELECT id, description, schema_source, source, created_at, updated_at FROM datasets ORDER BY id"
            ) do |rs|
              records << dataset_from_row(rs)
            end
            records
          end
        end

        def get_dataset(id : String) : DatasetRecord?
          @lock.synchronize do
            @db.query_one?(
              "SELECT id, description, schema_source, source, created_at, updated_at FROM datasets WHERE id = ? LIMIT 1",
              id,
              as: {String, String?, String?, String?, String, String},
            ).try { |row| dataset_from_tuple(row) }
          end
        end

        def upsert_dataset(dataset : DatasetRecord) : DatasetRecord
          @lock.synchronize do
            @db.exec(
              "INSERT INTO datasets (id, description, schema_source, source, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) " \
              "ON CONFLICT(id) DO UPDATE SET description = excluded.description, schema_source = excluded.schema_source, source = excluded.source, updated_at = excluded.updated_at",
              dataset.id,
              dataset.description,
              dataset.schema_source,
              dataset.source,
              dataset.created_at,
              dataset.updated_at,
            )
          end
          dataset
        end

        def delete_dataset(id : String) : Bool
          @lock.synchronize do
            result = @db.exec("DELETE FROM datasets WHERE id = ?", id)
            @db.exec("DELETE FROM dataset_items WHERE dataset_id = ?", id)
            result.rows_affected > 0
          end
        end

        def list_items(dataset_id : String) : Array(ItemRecord)
          @lock.synchronize do
            records = [] of ItemRecord
            @db.query_each(
              "SELECT id, payload, created_at, updated_at FROM dataset_items WHERE dataset_id = ? ORDER BY id",
              dataset_id,
            ) do |rs|
              records << item_from_row(rs)
            end
            records
          end
        end

        def add_items(dataset_id : String, items : Array(ItemRecord)) : Array(ItemRecord)
          @lock.synchronize do
            items.each do |item|
              @db.exec(
                "INSERT INTO dataset_items (dataset_id, id, payload, created_at, updated_at) VALUES (?, ?, ?, ?, ?) " \
                "ON CONFLICT(dataset_id, id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at",
                dataset_id,
                item.id,
                item.payload.to_json,
                item.created_at,
                item.updated_at,
              )
            end
          end
          items
        end

        def update_item(dataset_id : String, item_id : String, payload : AnyHash) : ItemRecord?
          @lock.synchronize do
            current = @db.query_one?(
              "SELECT created_at FROM dataset_items WHERE dataset_id = ? AND id = ? LIMIT 1",
              dataset_id,
              item_id,
              as: String,
            )
            return nil unless current

            updated = ItemRecord.new(
              id: item_id,
              payload: payload,
              created_at: current,
              updated_at: Time.utc.to_s,
            )
            @db.exec(
              "UPDATE dataset_items SET payload = ?, updated_at = ? WHERE dataset_id = ? AND id = ?",
              updated.payload.to_json,
              updated.updated_at,
              dataset_id,
              item_id,
            )
            updated
          end
        end

        def delete_item(dataset_id : String, item_id : String) : Bool
          @lock.synchronize do
            @db.exec(
              "DELETE FROM dataset_items WHERE dataset_id = ? AND id = ?",
              dataset_id,
              item_id,
            ).rows_affected > 0
          end
        end

        private def normalize_path(path : String) : String
          expanded = ::File.expand_path(path)
          return ::File.join(expanded, "datasets.sqlite3") if Dir.exists?(expanded)
          return expanded if ::File.extname(expanded).downcase.in?(".db", ".sqlite", ".sqlite3")
          ::File.join(expanded, "datasets.sqlite3")
        end

        private def migrate! : Nil
          @lock.synchronize do
            @db.exec("PRAGMA journal_mode = WAL")
            @db.exec("PRAGMA foreign_keys = ON")
            @db.exec(<<-SQL)
              CREATE TABLE IF NOT EXISTS datasets (
                id TEXT PRIMARY KEY,
                description TEXT,
                schema_source TEXT,
                source TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
              SQL
            @db.exec(<<-SQL)
              CREATE TABLE IF NOT EXISTS dataset_items (
                dataset_id TEXT NOT NULL,
                id TEXT NOT NULL,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (dataset_id, id),
                FOREIGN KEY (dataset_id) REFERENCES datasets(id) ON DELETE CASCADE
              )
              SQL
          end
        end

        private def dataset_from_row(rs) : DatasetRecord
          DatasetRecord.new(
            id: rs.read(String),
            description: rs.read(String?),
            schema_source: rs.read(String?),
            source: rs.read(String?),
            created_at: rs.read(String),
            updated_at: rs.read(String),
          )
        end

        private def dataset_from_tuple(row : Tuple(String, String?, String?, String?, String, String)) : DatasetRecord
          DatasetRecord.new(
            id: row[0],
            description: row[1],
            schema_source: row[2],
            source: row[3],
            created_at: row[4],
            updated_at: row[5],
          )
        end

        private def item_from_row(rs) : ItemRecord
          ItemRecord.new(
            id: rs.read(String),
            payload: JSON.parse(rs.read(String)).as_h,
            created_at: rs.read(String),
            updated_at: rs.read(String),
          )
        end
      end
    end
  end
end
