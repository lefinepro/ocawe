module CogniCore
  module CLI
    class Main
      struct TriggerResponse
        getter status_code : Int32
        getter body : String

        def initialize(@status_code : Int32, @body : String)
        end
      end

      alias TriggerInvoker = Proc(String, String, TriggerResponse)

      private DEFAULT_PORT             = 4111
      private DEFAULT_TRIGGER_BASE_URL = "http://127.0.0.1:4111"
      private PROJECT_ROOT             = File.expand_path("../..", __DIR__)
      private RUNTIME_ENTRY            = "#{PROJECT_ROOT}/src/cogni.cr"
      private RUNTIME_BIN              = "#{PROJECT_ROOT}/build/cognicore"
      private DEV_RUNTIME_BIN          = "#{PROJECT_ROOT}/build/cognicore-dev"
      private WORKFLOWS_PATH           = "#{PROJECT_ROOT}/src/workflows"
      private AGENTS_PATH              = "#{PROJECT_ROOT}/agents"
      private TOOLS_PATH               = "#{PROJECT_ROOT}/tools"
      private BOOTSTRAP_CRYSTAL        = "#{PROJECT_ROOT}/scripts/bootstrap-crystal.sh"
      private TRIGGER_COMMANDS         = Set{"workflow", "agent", "skill", "function", "tool", "support"}
      private CORE_COMMANDS            = Set{"build", "dev", "up", "workflow", "agent", "skill", "function", "tool", "support", "-v", "--version", "-h", "--help"}

      def initialize(@trigger_invoker : TriggerInvoker = ->(url : String, body : String) {
                       response = HTTP::Client.post(
                         url,
                         headers: HTTP::Headers{"Content-Type" => "application/json"},
                         body: body,
                       )
                       TriggerResponse.new(response.status_code, response.body)
                     })
      end

      def run(args : Array(String), program_name : String = PROGRAM_NAME) : Nil
        workflow_alias = workflow_alias_from_program_name(program_name)
        command = args.shift?

        if workflow_alias
          if command
            unless builtin_command?(command)
              run_trigger_command("workflow", workflow_alias, [command] + args)
              return
            end
          else
            run_trigger_command("workflow", workflow_alias, [] of String)
            return
          end
        end

        case command
        when "build"
          build(args)
        when "dev"
          dev(args)
        when "up"
          up(args)
        when "workflow", "agent", "skill", "function", "tool", "support"
          trigger_kind = command.not_nil!
          target_id = args.shift?
          unless target_id
            print_trigger_help(trigger_kind)
            exit(1)
          end
          run_trigger_command(trigger_kind, target_id, args)
        when "-v", "--version"
          puts CogniCore::VERSION
        when "-h", "--help"
          print_help
        else
          STDERR.puts "Unknown command: #{command}" if command
          print_help
          exit(1)
        end
      end

      private def print_help : Nil
        puts <<-TXT
          Usage: cogni <command> [options]

          Commands:
            build [--release] [--output PATH]
                Build runtime binary.
            dev [--port N] [--interval SECONDS] [--config-rcl PATH]
                Watch workflows/global agents/tools, recompile and restart runtime in dev mode.
            up [--port N] [--workflows-root PATH] [--config-rcl PATH]
                Auto-build release runtime binary and start server.
            workflow <workflow_id> [args ...] [--base-url URL] [--run-id ID] [--resource-id ID] [--input-json JSON]
                Trigger workflow by id.
            agent <agent_id> [args ...] [--base-url URL] [--input-json JSON] [--prompt TEXT] [--system TEXT] [--metadata-json JSON]
                Trigger agent by id.
            skill <skill_id> [args ...] [--base-url URL] [--input-json JSON]
                Trigger skill by id.
            function <function_id> [args ...] [--base-url URL] [--run-id ID] [--input-json JSON]
                Trigger function by id.
            tool <tool_id> [args ...]
                Alias of function trigger (tool id -> /v1/triggers/functions/:id).
            support <support_id> [args ...]
                Alias of skill trigger (support id -> /v1/triggers/skills/:id).
            -v, --version
                Print version.
            -h, --help
                Show this help.

          Examples:
            cogni workflow solver
            cogni workflow solver task=deploy env=prod
            cogni agent code-reviewer --prompt "review this diff"
            cogni tool project_healthcheck
            cogni support onboarding-check
        TXT
      end

      private def print_trigger_help(kind : String) : Nil
        puts <<-TXT
          Usage:
            cogni #{kind} <id> [args ...] [--base-url URL] [--input-json JSON]

          Argument mapping:
            key=value   -> payload key/value (or payload.input key/value for workflow/function/tool)
            value       -> appended to payload.args (or payload.input.args for workflow/function/tool)

          Notes:
            tool maps to function trigger endpoint.
            support maps to skill trigger endpoint.
        TXT
      end

      private def trigger_endpoint_for(kind : String) : String
        case kind
        when "workflow"
          "workflows"
        when "agent"
          "agents"
        when "skill", "support"
          "skills"
        when "function", "tool"
          "functions"
        else
          raise "unsupported trigger kind: #{kind}"
        end
      end

      private def parse_cli_tokens(tokens : Array(String)) : Tuple(Hash(String, JSON::Any), Array(JSON::Any))
        named = {} of String => JSON::Any
        positional = [] of JSON::Any

        tokens.each do |token|
          separator = token.index('=')
          if separator && separator > 0
            key = token[0, separator]
            raw = token[separator + 1, token.bytesize - separator - 1]
            named[key] = parse_cli_value(raw)
          else
            positional << parse_cli_value(token)
          end
        end

        {named, positional}
      end

      private def merge_cli_tokens!(target : Hash(String, JSON::Any), named : Hash(String, JSON::Any), positional : Array(JSON::Any)) : Nil
        named.each do |key, value|
          target[key] = value
        end

        return if positional.empty?

        existing_args = target["args"]?.try(&.as_a?) || [] of JSON::Any
        merged_args = existing_args + positional
        target["args"] = JSON.parse(merged_args.to_json)
      end

      private def parse_input_json(value : String) : Hash(String, JSON::Any)
        parsed = JSON.parse(value)
        parsed.as_h
      rescue ex
        raise "invalid json value: #{ex.message}"
      end

      private def parse_cli_value(value : String) : JSON::Any
        JSON.parse(value)
      rescue
        json_any(value)
      end

      private def print_json_or_raw(body : String, io : IO = STDOUT) : Nil
        return if body.empty?

        parsed = JSON.parse(body)
        io.puts parsed.to_pretty_json
      rescue
        io.puts body
      end

      private def success_status?(status_code : Int32) : Bool
        status_code >= 200 && status_code < 300
      end

      private def workflow_alias_from_program_name(program_name : String) : String?
        name = File.basename(program_name)
        return nil if name.empty?
        return nil if name == "cogni"
        return nil if CORE_COMMANDS.includes?(name)
        return nil if TRIGGER_COMMANDS.includes?(name)
        name
      end

      private def builtin_command?(command : String) : Bool
        CORE_COMMANDS.includes?(command)
      end

      private def json_any(value)
        JSON.parse(value.to_json)
      end

      private def trimmed_base_url(base_url : String) : String
        base_url.ends_with?("/") ? base_url[0, base_url.size - 1] : base_url
      end
    end
  end
end
