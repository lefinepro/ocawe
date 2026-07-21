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

      def resources : Array(CawfileResource)
        @cawfile.try(&.resources) || [] of CawfileResource
      end
    end

    class WorkflowLocator
      def initialize(
        @preferred_root : String = "./src/workflows",
        generated_root : String? = nil,
      )
        @generated_root = generated_root
        if generated_root && File.expand_path(generated_root) == File.expand_path(@preferred_root)
          @generated_root = nil
        end
      end

      def list_workflows : Array(WorkflowBundle)
        bundles = [] of WorkflowBundle
        root_bundles = root_cawfile_bundles
        bundles.concat(root_bundles)
        seen = root_bundles.map(&.id).to_set

        workflow_roots.each do |entry|
          ids = Set(String).new
          each_bundle_dir(entry[:path]) { |name| ids << name }
          ids.to_a.sort.each do |id|
            next if seen.includes?(id)
            begin
              bundles << bundle_from_dir(id, File.join(entry[:path], id), entry[:source_type])
              seen << id
            rescue
            end
          end
        end

        bundles
      end

      def resolve(id : String) : WorkflowBundle
        resolve?(id) || raise "unknown workflow bundle: #{id}"
      end

      def resolve?(id : String) : WorkflowBundle?
        resolve?(id, root_cawfile_bundles)
      end

      private def resolve?(id : String, root_bundles : Array(WorkflowBundle)) : WorkflowBundle?
        root_bundles.each do |bundle|
          return bundle if bundle.id == id
        end

        preferred_dir = File.join(@preferred_root, id)
        if Dir.exists?(preferred_dir)
          return bundle_from_dir(id, preferred_dir, "preferred")
        end

        if generated_root = @generated_root
          generated_dir = File.join(generated_root, id)
          if Dir.exists?(generated_dir)
            return bundle_from_dir(id, generated_dir, "generated")
          end
        end

        nil
      end

      private def workflow_roots
        roots = [{path: @preferred_root, source_type: "preferred"}]
        if generated_root = @generated_root
          roots << {path: generated_root, source_type: "generated"}
        end
        roots
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
