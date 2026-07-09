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
      getter service : Bool

      def initialize(
        @id : String,
        @root_path : String,
        @workflow_file : String,
        @agents_dir : String,
        @skills_dir : String,
        @source_root_type : String,
        @cawfile : CawfileBundle? = nil,
        @service : Bool = false,
      )
      end
    end

    class WorkflowLocator
      def initialize(@preferred_root : String = "./src/workflows")
      end

      def list_workflows : Array(WorkflowBundle)
        ids = Set(String).new
        bundles = [] of WorkflowBundle

        bundles.concat(root_cawfile_bundles)

        each_bundle_dir(@preferred_root) { |name| ids << name }

        ids.to_a.sort.each do |id|
          begin
            if bundle = resolve?(id)
              bundles << bundle
            end
          rescue
          end
        end

        bundles
      end

      def resolve(id : String) : WorkflowBundle
        resolve?(id) || raise "unknown workflow bundle: #{id}"
      end

      def resolve?(id : String) : WorkflowBundle?
        root_cawfile_bundles.each do |bundle|
          return bundle if bundle.id == id
        end

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
            id: cawfile.id,
            root_path: dir,
            workflow_file: cawfile_path || File.join(dir, ".caw"),
            agents_dir: File.join(dir, "agents"),
            skills_dir: File.join(dir, "skills"),
            source_root_type: source_type,
            cawfile: cawfile,
            service: cawfile.service,
          )
        end

        # Fallback: .acd.cr or .cr
        workflow_file = File.join(dir, "#{id}.acd.cr")
        if !File.file?(workflow_file)
          workflow_file = File.join(dir, "#{id}.cr")
        end
        raise "#{dir}: missing executable workflow file (#{id}.acd.cr or #{id}.cr)" unless File.file?(workflow_file)

        WorkflowBundle.new(
          id: id,
          root_path: dir,
          workflow_file: workflow_file,
          agents_dir: File.join(dir, "agents"),
          skills_dir: File.join(dir, "skills"),
          source_root_type: source_type,
        )
      end

      private def root_cawfile_bundles : Array(WorkflowBundle)
        cawfile_path = ACD::Discovery::CawfileLoader.find_cawfile(@preferred_root)
        return [] of WorkflowBundle unless cawfile_path

        ACD::Discovery::CawfileLoader.load_all(@preferred_root).map do |cawfile|
          WorkflowBundle.new(
            id: cawfile.id,
            root_path: @preferred_root,
            workflow_file: cawfile_path,
            agents_dir: File.join(@preferred_root, "agents"),
            skills_dir: File.join(@preferred_root, "skills"),
            source_root_type: "root-cawfile",
            cawfile: cawfile,
            service: cawfile.service,
          )
        end
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
