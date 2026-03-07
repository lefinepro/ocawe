require "set"

module ACD
  module Discovery
    struct WorkflowBundle
      getter id : String
      getter root_path : String
      getter workflow_file : String
      getter agents_dir : String
      getter skills_dir : String
      getter source_root_type : String

      def initialize(@id : String, @root_path : String, @workflow_file : String, @agents_dir : String, @skills_dir : String, @source_root_type : String)
      end
    end

    class WorkflowLocator
      def initialize(@preferred_root : String = "./src/workflows", @fallback_root : String = "./workflows")
      end

      def list_workflows : Array(WorkflowBundle)
        ids = Set(String).new

        each_bundle_dir(@preferred_root) { |name| ids << name }
        each_bundle_dir(@fallback_root) { |name| ids << name }

        ids.to_a.sort.compact_map { |id| resolve?(id) }
      end

      def resolve(id : String) : WorkflowBundle
        resolve?(id) || raise "unknown workflow bundle: #{id}"
      end

      def resolve?(id : String) : WorkflowBundle?
        preferred_dir = File.join(@preferred_root, id)
        if Dir.exists?(preferred_dir)
          return bundle_from_dir(id, preferred_dir, "preferred")
        end

        fallback_dir = File.join(@fallback_root, id)
        if Dir.exists?(fallback_dir)
          return bundle_from_dir(id, fallback_dir, "fallback")
        end

        nil
      end

      private def bundle_from_dir(id : String, dir : String, source_type : String)
        workflow_file = File.join(dir, "#{id}.acd.cr")
        raise "#{dir}: missing executable workflow file #{workflow_file}" unless File.file?(workflow_file)

        WorkflowBundle.new(
          id: id,
          root_path: dir,
          workflow_file: workflow_file,
          agents_dir: File.join(dir, "agents"),
          skills_dir: File.join(dir, "skills"),
          source_root_type: source_type,
        )
      end

      private def each_bundle_dir(root : String, &block : String ->)
        return unless Dir.exists?(root)

        Dir.each_child(root) do |name|
          path = File.join(root, name)
          next unless Dir.exists?(path)
          yield name
        end
      end
    end
  end
end
