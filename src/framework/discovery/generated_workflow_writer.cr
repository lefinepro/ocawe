require "file_utils"
require "random/secure"
require "./cawfile_loader"
require "./generated_workflow_request"

module ACD
  module Discovery
    class GeneratedWorkflowNotFoundError < Exception
    end

    class GeneratedWorkflowProtectionError < Exception
    end

    struct GeneratedWorkflowArtifact
      getter id : String
      getter content : String
      getter relative_path : String
      getter workflow_dir : String

      def initialize(@id : String, @content : String, @relative_path : String, @workflow_dir : String)
      end
    end

    struct GeneratedWorkflowReplacementArtifact
      getter id : String
      getter content : String
      getter previous_content : String
      getter relative_path : String
      getter workflow_dir : String
      getter cawfile_path : String

      def initialize(
        @id : String,
        @content : String,
        @previous_content : String,
        @relative_path : String,
        @workflow_dir : String,
        @cawfile_path : String,
      )
      end
    end

    struct GeneratedWorkflowDeletionArtifact
      getter id : String
      getter content : String
      getter relative_path : String
      getter workflow_dir : String
      getter cawfile_path : String
      getter staged_path : String

      def initialize(
        @id : String,
        @content : String,
        @relative_path : String,
        @workflow_dir : String,
        @cawfile_path : String,
        @staged_path : String,
      )
      end
    end

    class GeneratedWorkflowWriter
      GENERATED_MARKER = "#+ocawe-generated: true"

      getter root : String

      def initialize(root : String)
        @root = File.expand_path(root)
      end

      def create(request : GeneratedWorkflowRequest, known_ids : Array(String) = [] of String) : GeneratedWorkflowArtifact
        if known_ids.includes?(request.id)
          raise GeneratedWorkflowConflictError.new("workflow already exists: #{request.id}")
        end

        FileUtils.mkdir_p(root)
        workflow_dir = workflow_dir_for(request.id)
        if File.exists?(workflow_dir) || Dir.exists?(workflow_dir)
          raise GeneratedWorkflowConflictError.new("workflow already exists: #{request.id}")
        end

        content = render(request)
        temporary_path = ""
        created_dir = false

        begin
          Dir.mkdir(workflow_dir)
          created_dir = true
          cawfile_path = File.join(workflow_dir, "Cawfile")
          temporary_path = File.join(workflow_dir, ".Cawfile.tmp-#{Random::Secure.hex(8)}")
          File.write(temporary_path, content)
          File.rename(temporary_path, cawfile_path)
          validate_cawfile!(workflow_dir, request.id)

          GeneratedWorkflowArtifact.new(
            id: request.id,
            content: content,
            relative_path: File.join(request.id, "Cawfile"),
            workflow_dir: workflow_dir,
          )
        rescue ex
          File.delete(temporary_path) if !temporary_path.empty? && File.exists?(temporary_path)
          FileUtils.rm_rf(workflow_dir) if created_dir
          raise ex
        end
      end

      def rollback(artifact : GeneratedWorkflowArtifact) : Nil
        expected = workflow_dir_for(artifact.id)
        FileUtils.rm_rf(expected) if artifact.workflow_dir == expected && Dir.exists?(expected)
      end

      def replace_cawfile(id : String, content : String) : GeneratedWorkflowReplacementArtifact
        GeneratedWorkflowRequest.validate_id!(id)
        if content.bytesize > GeneratedWorkflowRequest::MAX_BODY_BYTES
          raise GeneratedWorkflowPayloadTooLargeError.new("cawfile exceeds #{GeneratedWorkflowRequest::MAX_BODY_BYTES} bytes")
        end
        validate_replacement_content!(content)

        workflow_dir = workflow_dir_for(id)
        unless Dir.exists?(workflow_dir) && !File.symlink?(workflow_dir)
          raise GeneratedWorkflowNotFoundError.new("generated workflow not found: #{id}")
        end

        cawfile_path = File.join(workflow_dir, "Cawfile")
        unless File.file?(cawfile_path) && !File.symlink?(cawfile_path)
          raise GeneratedWorkflowNotFoundError.new("generated workflow Cawfile not found: #{id}")
        end

        previous_content = File.read(cawfile_path)
        unless generated_content?(previous_content)
          raise GeneratedWorkflowProtectionError.new("workflow is not managed by the generated workflow API: #{id}")
        end

        temporary_path = File.join(workflow_dir, ".Cawfile.replace-#{Random::Secure.hex(8)}")
        begin
          File.write(temporary_path, content)
          File.rename(temporary_path, cawfile_path)
          validate_cawfile_loads!(workflow_dir, id)
          GeneratedWorkflowReplacementArtifact.new(
            id: id,
            content: content,
            previous_content: previous_content,
            relative_path: File.join(id, "Cawfile"),
            workflow_dir: workflow_dir,
            cawfile_path: cawfile_path,
          )
        rescue ex
          File.delete(temporary_path) if File.exists?(temporary_path)
          File.write(temporary_path, previous_content)
          File.rename(temporary_path, cawfile_path)
          raise ex
        end
      end

      def rollback_replace(artifact : GeneratedWorkflowReplacementArtifact) : Nil
        GeneratedWorkflowRequest.validate_id!(artifact.id)
        return unless artifact.workflow_dir == workflow_dir_for(artifact.id)
        temporary_path = File.join(artifact.workflow_dir, ".Cawfile.rollback-#{Random::Secure.hex(8)}")
        begin
          File.write(temporary_path, artifact.previous_content)
          File.rename(temporary_path, artifact.cawfile_path)
        ensure
          File.delete(temporary_path) if File.exists?(temporary_path)
        end
      end

      # Atomically hides a generated Cawfile from discovery while retaining an
      # in-directory tombstone that can be restored if the runtime reload fails.
      def stage_delete(id : String) : GeneratedWorkflowDeletionArtifact
        GeneratedWorkflowRequest.validate_id!(id)
        workflow_dir = workflow_dir_for(id)
        unless Dir.exists?(workflow_dir)
          raise GeneratedWorkflowNotFoundError.new("generated workflow not found: #{id}")
        end
        if File.symlink?(workflow_dir)
          raise GeneratedWorkflowProtectionError.new("generated workflow directory must not be a symlink: #{id}")
        end

        cawfile_path = File.join(workflow_dir, "Cawfile")
        unless File.file?(cawfile_path) && !File.symlink?(cawfile_path)
          raise GeneratedWorkflowNotFoundError.new("generated workflow Cawfile not found: #{id}")
        end

        content = File.read(cawfile_path)
        unless generated_content?(content)
          raise GeneratedWorkflowProtectionError.new("workflow is not managed by the generated workflow API: #{id}")
        end

        staged_path = File.join(workflow_dir, ".Cawfile.delete-#{Random::Secure.hex(8)}")
        File.rename(cawfile_path, staged_path)
        GeneratedWorkflowDeletionArtifact.new(
          id: id,
          content: content,
          relative_path: File.join(id, "Cawfile"),
          workflow_dir: workflow_dir,
          cawfile_path: cawfile_path,
          staged_path: staged_path,
        )
      end

      # Finalizes a staged deletion. Only the staged Cawfile is removed; an
      # otherwise-empty generated directory is also cleaned up.
      def commit_delete(artifact : GeneratedWorkflowDeletionArtifact) : Nil
        validate_deletion_artifact!(artifact)
        unless File.file?(artifact.staged_path) && !File.symlink?(artifact.staged_path)
          raise GeneratedWorkflowProtectionError.new("staged generated Cawfile is missing: #{artifact.id}")
        end

        File.delete(artifact.staged_path)
        if Dir.exists?(artifact.workflow_dir) && Dir.children(artifact.workflow_dir).empty?
          Dir.delete(artifact.workflow_dir)
        end
      end

      # Restores the exact staged Cawfile. If finalization removed the tombstone
      # before failing, the captured content is written back atomically.
      def rollback_delete(artifact : GeneratedWorkflowDeletionArtifact) : Nil
        validate_deletion_artifact!(artifact)
        if File.file?(artifact.cawfile_path) && !File.symlink?(artifact.cawfile_path)
          existing = File.read(artifact.cawfile_path)
          return if existing == artifact.content
          raise GeneratedWorkflowProtectionError.new("refusing to overwrite restored Cawfile: #{artifact.id}")
        end
        if File.exists?(artifact.cawfile_path) || File.symlink?(artifact.cawfile_path)
          raise GeneratedWorkflowProtectionError.new("refusing to overwrite restored Cawfile path: #{artifact.id}")
        end

        if Dir.exists?(artifact.workflow_dir)
          if File.symlink?(artifact.workflow_dir)
            raise GeneratedWorkflowProtectionError.new("generated workflow directory must not be a symlink: #{artifact.id}")
          end
        else
          Dir.mkdir(artifact.workflow_dir)
        end

        if File.file?(artifact.staged_path) && !File.symlink?(artifact.staged_path)
          File.rename(artifact.staged_path, artifact.cawfile_path)
          return
        end
        if File.exists?(artifact.staged_path) || File.symlink?(artifact.staged_path)
          raise GeneratedWorkflowProtectionError.new("invalid staged generated Cawfile: #{artifact.id}")
        end

        temporary_path = File.join(artifact.workflow_dir, ".Cawfile.restore-#{Random::Secure.hex(8)}")
        begin
          File.write(temporary_path, artifact.content)
          File.rename(temporary_path, artifact.cawfile_path)
        ensure
          File.delete(temporary_path) if File.exists?(temporary_path)
        end
      end

      private def workflow_dir_for(id : String) : String
        path = File.expand_path(File.join(root, id))
        prefix = root.ends_with?('/') ? root : "#{root}/"
        unless path.starts_with?(prefix)
          raise GeneratedWorkflowValidationError.new("workflow path escapes generated workflows root")
        end
        path
      end

      private def validate_deletion_artifact!(artifact : GeneratedWorkflowDeletionArtifact) : Nil
        GeneratedWorkflowRequest.validate_id!(artifact.id)
        expected_dir = workflow_dir_for(artifact.id)
        expected_cawfile = File.join(expected_dir, "Cawfile")
        staged_prefix = File.join(expected_dir, ".Cawfile.delete-")
        valid = artifact.workflow_dir == expected_dir &&
                artifact.cawfile_path == expected_cawfile &&
                File.dirname(artifact.staged_path) == expected_dir &&
                artifact.staged_path.starts_with?(staged_prefix) &&
                generated_content?(artifact.content)
        unless valid
          raise GeneratedWorkflowProtectionError.new("invalid generated workflow deletion artifact")
        end
      end

      private def generated_content?(content : String) : Bool
        content.each_line.any? { |line| line.strip == GENERATED_MARKER }
      end

      private def validate_cawfile!(workflow_dir : String, id : String) : Nil
        validate_cawfile_loads!(workflow_dir, id)
        bundle = CawfileLoader.load(workflow_dir, id)
        dsl = bundle.try(&.dsl_source)
        unless dsl && dsl.any? { |line| line.includes?(%q(agent "assistant")) }
          raise "generated Cawfile is missing its initial agent node"
        end
      end

      private def validate_cawfile_loads!(workflow_dir : String, id : String) : Nil
        bundle = CawfileLoader.load(workflow_dir, id)
        unless bundle && bundle.id == id
          raise "generated Cawfile did not load workflow #{id}"
        end
      end

      private def validate_replacement_content!(content : String) : Nil
        unless generated_content?(content)
          raise GeneratedWorkflowValidationError.new("replacement Cawfile must include #{GENERATED_MARKER}")
        end
        if content.includes?('\0')
          raise GeneratedWorkflowValidationError.new("replacement Cawfile must not contain NUL characters")
        end
      end

      private def render(request : GeneratedWorkflowRequest) : String
        encoded_id = request.id.bytes.map { |byte| byte.to_s(16) }.join
        input_type = "Generated#{encoded_id}Input"
        output_type = "Generated#{encoded_id}Output"
        lines = [
          "# Generated by Ocawe workflow creation API.",
          "#+name: #{header_value(request.name)}",
        ]
        add_header(lines, "description", request.description)
        add_header(lines, "tags", cawfile_tag(request.tag))
        lines << GENERATED_MARKER
        add_header(lines, "ocawe-schedule", request.schedule)
        add_header(lines, "ocawe-trigger-message", request.trigger_message)
        add_header(lines, "ocawe-conversation-id", request.conversation_id)
        add_header(lines, "ocawe-user-id", request.user_id)
        add_header(lines, "ocawe-environment-id", request.environment_id)
        lines.concat([
          "",
          "struct #{input_type}",
          "  include JSON::Serializable",
          "  getter input : JSON::Any?",
          "end",
          "",
          "struct #{output_type}",
          "  include JSON::Serializable",
          "  getter output : JSON::Any?",
          "end",
          "",
          "@[Validate(#{input_type}, #{output_type})]",
          "workflow #{request.id.to_json} do",
        ])

        agent = "  agent \"assistant\", prompt: #{request.prompt.to_json}"
        agent += ", model: #{request.model.to_json}" if request.model
        lines << agent
        lines << "end"
        lines.join("\n") + "\n"
      end

      private def add_header(lines : Array(String), key : String, value : String?) : Nil
        lines << "#+#{key}: #{header_value(value)}" if value
      end

      private def header_value(value : String) : String
        value.gsub(/\s+/, " ").strip
      end

      private def cawfile_tag(tag : String?) : String?
        return nil unless tag
        tag.starts_with?('#') ? tag[1..] : tag
      end
    end
  end
end
