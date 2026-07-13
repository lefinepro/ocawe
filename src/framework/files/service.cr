require "base64"
require "file_utils"
require "json"
require "../dataset/service"

module Ocawe
  module Files
    alias AnyHash = Hash(String, JSON::Any)

    class Service
      DATASET_ID = "ocawe_files"

      def initialize(@dataset_service : Ocawe::Dataset::Service, @root : String = "./.ocawe/files")
        Dir.mkdir_p(@root)
      end

      def create(filename : String, content : String, purpose : String = "assistants") : AnyHash
        ensure_dataset
        file_id = "file_#{Random::Secure.hex(12)}"
        storage_path = path_for(file_id)
        File.write(storage_path, content)

        payload = file_payload(
          id: file_id,
          filename: filename.empty? ? file_id : filename,
          purpose: purpose.empty? ? "assistants" : purpose,
          bytes: content.bytesize,
          storage_path: storage_path,
        )
        @dataset_service.add_items(DATASET_ID, [payload])
        public_file_payload(file_id, payload)
      end

      def list : Array(AnyHash)
        ensure_dataset
        @dataset_service.list_items(DATASET_ID).map { |item| public_file_payload(item.id, item.payload) }
      end

      def get(file_id : String) : AnyHash?
        ensure_dataset
        item_for(file_id).try { |item| public_file_payload(item.id, item.payload) }
      end

      def content(file_id : String) : String?
        item = item_for(file_id)
        return nil unless item
        storage_path = item.payload["storage_path"]?.try(&.as_s?) || path_for(file_id)
        return nil unless File.file?(storage_path)
        File.read(storage_path)
      end

      def resource(file_id : String) : AnyHash?
        metadata = get(file_id)
        content = content(file_id)
        return nil unless metadata && content

        resource = metadata.dup
        resource["content_base64"] = json_any(Base64.strict_encode(content))
        resource
      end

      def delete(file_id : String) : Bool
        item = item_for(file_id)
        storage_path = item.try(&.payload["storage_path"]?.try(&.as_s?)) || path_for(file_id)
        deleted = @dataset_service.delete_item(DATASET_ID, file_id)
        File.delete(storage_path) if deleted && File.exists?(storage_path)
        deleted
      rescue
        false
      end

      private def ensure_dataset : Nil
        return if @dataset_service.get_dataset(DATASET_ID)

        @dataset_service.create_dataset(DATASET_ID, description: "OpenAI-compatible file uploads")
      rescue ex
        raise ex unless (ex.message || "").includes?("already exists")
      end

      private def item_for(file_id : String) : Ocawe::Dataset::ItemRecord?
        return nil unless valid_file_id?(file_id)
        ensure_dataset
        @dataset_service.list_items(DATASET_ID).find { |item| item.id == file_id }
      end

      private def valid_file_id?(file_id : String) : Bool
        file_id.match(/\Afile_[a-zA-Z0-9]+\z/) ? true : false
      end

      private def path_for(file_id : String) : String
        File.join(@root, "#{file_id}.bin")
      end

      private def file_payload(
        id : String,
        filename : String,
        purpose : String,
        bytes : Int32,
        storage_path : String,
      ) : AnyHash
        {
          "id"           => json_any(id),
          "object"       => json_any("file"),
          "bytes"        => json_any(bytes),
          "created_at"   => json_any(Time.utc.to_unix),
          "filename"     => json_any(filename),
          "purpose"      => json_any(purpose),
          "storage_path" => json_any(storage_path),
        } of String => JSON::Any
      end

      private def public_file_payload(file_id : String, payload : AnyHash) : AnyHash
        {
          "id"         => json_any(file_id),
          "object"     => json_any("file"),
          "bytes"      => payload["bytes"]? || json_any(0),
          "created_at" => payload["created_at"]? || json_any(Time.utc.to_unix),
          "filename"   => payload["filename"]? || json_any(file_id),
          "purpose"    => payload["purpose"]? || json_any("assistants"),
        } of String => JSON::Any
      end

      private def json_any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
