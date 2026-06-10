require "set"
require "./cawfile_loader"

module ACD
  module Discovery
    struct WorkflowBundle
      getter id : String
      getter root_path : String
      getter workflow_file : String
      getter agents_dir : String
      getter skills_dir : String
      getter source_root_type : String
      getter cawfile : CawfileBundle?

      def initialize(@id : String, @root_path : String, @workflow_file : String, @agents_dir : String, @skills_dir : String, @source_root_type : String, @cawfile : CawfileBundle? = nil)
      end
    end

    class WorkflowLocator
      def initialize(@preferred_root : String = "./src/workflows")
      end

      def list_workflows : Array(WorkflowBundle)
        ids = Set(String).new

        each_bundle_dir(@preferred_root) { |name| ids << name }

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

        nil
      end

      private def bundle_from_dir(id : String, dir : String, source_type : String)
        # Primary: Cawfile / .caw
        cawfile = ACD::Discovery::CawfileLoader.load(dir, id)

        if cawfile
          cawfile_path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
          return WorkflowBundle.new(
            id: id,
            root_path: dir,
            workflow_file: cawfile_path || File.join(dir, ".caw"),
            agents_dir: File.join(dir, "agents"),
            skills_dir: File.join(dir, "skills"),
            source_root_type: source_type,
            cawfile: cawfile,
          )
        end

        # Fallback: .acd.cr
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
