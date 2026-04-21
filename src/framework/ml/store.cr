require "json"

module Cogni
  module ML
    alias AnyHash = Hash(String, JSON::Any)

    struct ModelRecord
      include JSON::Serializable

      getter id : String
      getter description : String?
      getter task : String?
      getter base_model : String?
      getter adapter : String
      getter source : String?
      getter backends : Array(String)
      getter metadata : AnyHash?
      getter declared_from : String?
      getter created_at : String
      getter updated_at : String

      def initialize(
        @id : String,
        @description : String? = nil,
        @task : String? = nil,
        @base_model : String? = nil,
        @adapter : String = "cogni_ml",
        @source : String? = nil,
        @backends : Array(String) = [] of String,
        @metadata : AnyHash? = nil,
        @declared_from : String? = nil,
        @created_at : String = Time.utc.to_s,
        @updated_at : String = Time.utc.to_s
      )
      end
    end

    struct ArtifactRecord
      include JSON::Serializable

      getter id : String
      getter model_id : String
      getter kind : String
      getter status : String
      getter metadata : AnyHash
      getter created_at : String
      getter updated_at : String

      def initialize(
        @id : String,
        @model_id : String,
        @kind : String,
        @status : String,
        @metadata : AnyHash = {} of String => JSON::Any,
        @created_at : String = Time.utc.to_s,
        @updated_at : String = Time.utc.to_s
      )
      end
    end

    module Store
      abstract class Base
        abstract def list_models : Array(ModelRecord)
        abstract def get_model(id : String) : ModelRecord?
        abstract def upsert_model(model : ModelRecord) : ModelRecord
        abstract def list_artifacts(model_id : String? = nil) : Array(ArtifactRecord)
        abstract def add_artifact(artifact : ArtifactRecord) : ArtifactRecord
      end

      class InMemory < Base
        def initialize
          @models = {} of String => ModelRecord
          @artifacts = {} of String => ArtifactRecord
          @lock = Mutex.new
        end

        def list_models : Array(ModelRecord)
          @lock.synchronize { @models.values.to_a }
        end

        def get_model(id : String) : ModelRecord?
          @lock.synchronize { @models[id]? }
        end

        def upsert_model(model : ModelRecord) : ModelRecord
          @lock.synchronize do
            @models[model.id] = model
          end
          model
        end

        def list_artifacts(model_id : String? = nil) : Array(ArtifactRecord)
          @lock.synchronize do
            values = @artifacts.values.to_a
            model_id ? values.select { |artifact| artifact.model_id == model_id } : values
          end
        end

        def add_artifact(artifact : ArtifactRecord) : ArtifactRecord
          @lock.synchronize do
            @artifacts[artifact.id] = artifact
          end
          artifact
        end
      end

      class File < Base
        struct Snapshot
          include JSON::Serializable

          getter models : Array(ModelRecord)
          getter artifacts : Array(ArtifactRecord)

          def initialize(
            @models : Array(ModelRecord) = [] of ModelRecord,
            @artifacts : Array(ArtifactRecord) = [] of ArtifactRecord
          )
          end
        end

        def initialize(@root : String)
          @lock = Mutex.new
          Dir.mkdir_p(@root)
          @path = ::File.join(@root, "ml_registry.json")
        end

        def list_models : Array(ModelRecord)
          @lock.synchronize { snapshot.models }
        end

        def get_model(id : String) : ModelRecord?
          @lock.synchronize { snapshot.models.find { |model| model.id == id } }
        end

        def upsert_model(model : ModelRecord) : ModelRecord
          @lock.synchronize do
            snap = snapshot
            models = snap.models.dup
            idx = models.index { |entry| entry.id == model.id }
            if idx
              models[idx] = model
            else
              models << model
            end
            persist(Snapshot.new(models: models, artifacts: snap.artifacts.dup))
          end
          model
        end

        def list_artifacts(model_id : String? = nil) : Array(ArtifactRecord)
          @lock.synchronize do
            records = snapshot.artifacts
            model_id ? records.select { |artifact| artifact.model_id == model_id } : records
          end
        end

        def add_artifact(artifact : ArtifactRecord) : ArtifactRecord
          @lock.synchronize do
            snap = snapshot
            artifacts = snap.artifacts.reject { |entry| entry.id == artifact.id }
            artifacts << artifact
            persist(Snapshot.new(models: snap.models.dup, artifacts: artifacts))
          end
          artifact
        end

        private def snapshot : Snapshot
          return Snapshot.new unless ::File.exists?(@path)
          Snapshot.from_json(::File.read(@path))
        rescue
          Snapshot.new
        end

        private def persist(snapshot : Snapshot) : Nil
          ::File.write(@path, snapshot.to_json)
        end
      end
    end
  end
end
