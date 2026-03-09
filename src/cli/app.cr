require "option_parser"
require "http/client"
require "json"
require "../framework/cognicore/version"

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
            up [--port N] [--workflows-root PATH] [--fallback-workflows-root PATH] [--config-rcl PATH]
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

      private def run_trigger_command(kind : String, target_id : String, args : Array(String)) : Nil
        endpoint = trigger_endpoint_for(kind)
        base_url = ENV["COGNI_TRIGGER_BASE_URL"]? || DEFAULT_TRIGGER_BASE_URL
        run_id = nil.as(String?)
        resource_id = nil.as(String?)
        input_json = nil.as(Hash(String, JSON::Any)?)
        prompt = nil.as(String?)
        system = nil.as(String?)
        metadata_json = nil.as(Hash(String, JSON::Any)?)

        OptionParser.parse(args) do |parser|
          parser.on("--base-url URL", "Trigger API base URL") { |v| base_url = v }
          parser.on("--run-id ID", "Optional run id") { |v| run_id = v }
          parser.on("--resource-id ID", "Optional resource id") { |v| resource_id = v }
          parser.on("--input-json JSON", "Full request payload JSON object") { |v| input_json = parse_input_json(v) }
          parser.on("--prompt TEXT", "Agent prompt shortcut (maps to payload.input)") { |v| prompt = v }
          parser.on("--system TEXT", "Agent system message") { |v| system = v }
          parser.on("--metadata-json JSON", "Agent metadata JSON object") { |v| metadata_json = parse_input_json(v) }
          parser.on("-h", "--help", "Show trigger help") do
            print_trigger_help(kind)
            exit(0)
          end
        end

        payload = input_json ? input_json.not_nil!.dup : ({} of String => JSON::Any)
        named_args, positional_args = parse_cli_tokens(args)

        case endpoint
        when "workflows"
          input_data = payload["input"]?.try(&.as_h?) || ({} of String => JSON::Any)
          merge_cli_tokens!(input_data, named_args, positional_args)
          payload["input"] = JSON.parse(input_data.to_json) unless input_data.empty? && !payload.has_key?("input")
          payload["run_id"] = json_any(run_id) if run_id
          payload["resource_id"] = json_any(resource_id) if resource_id
        when "functions"
          input_data = payload["input"]?.try(&.as_h?) || ({} of String => JSON::Any)
          merge_cli_tokens!(input_data, named_args, positional_args)
          payload["input"] = JSON.parse(input_data.to_json) unless input_data.empty? && !payload.has_key?("input")
          payload["run_id"] = json_any(run_id) if run_id
        when "agents"
          merge_cli_tokens!(payload, named_args, positional_args)
          if prompt && !payload.has_key?("input") && !payload.has_key?("prompt") && !payload.has_key?("messages")
            payload["input"] = json_any(prompt)
          end
          payload["system"] = json_any(system) if system
          payload["metadata"] = JSON.parse(metadata_json.not_nil!.to_json) if metadata_json
        when "skills"
          merge_cli_tokens!(payload, named_args, positional_args)
        else
          raise "unsupported trigger endpoint: #{endpoint}"
        end

        url = "#{trimmed_base_url(base_url)}/v1/triggers/#{endpoint}/#{target_id}"

        begin
          response = @trigger_invoker.call(url, payload.to_json)
          if success_status?(response.status_code)
            print_json_or_raw(response.body)
          else
            STDERR.puts "[cogni] #{kind} trigger failed: HTTP #{response.status_code}"
            print_json_or_raw(response.body, io: STDERR)
            exit(1)
          end
        rescue ex
          STDERR.puts "[cogni] failed to call #{kind} trigger: #{ex.message}"
          exit(1)
        end
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

      private def build(args : Array(String)) : Nil
        release = true
        output = RUNTIME_BIN

        OptionParser.parse(args) do |parser|
          parser.on("--release", "Build release binary (default)") { release = true }
          parser.on("--debug", "Build non-release binary") { release = false }
          parser.on("--output PATH", "Output binary path") { |v| output = v }
        end

        abort_unless_success(build_runtime(release: release, output: output))
      end

      private def dev(args : Array(String)) : Nil
        port = DEFAULT_PORT
        interval = 1.0
        config_rcl = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("--port PORT", "Runtime port") { |v| port = v.to_i }
          parser.on("--interval SECONDS", "Watch interval") { |v| interval = v.to_f }
          parser.on("--config-rcl PATH", "RCL config path") { |v| config_rcl = v }
        end

        tracked = [WORKFLOWS_PATH, AGENTS_PATH, TOOLS_PATH]
        fingerprint = compute_fingerprint(tracked)

        abort_unless_success(build_runtime(release: false, output: DEV_RUNTIME_BIN))
        runtime = spawn_cmd(dev_runtime_cmd(port, config_rcl))

        Signal::INT.trap do
          terminate(runtime)
          exit(0)
        end

        loop do
          sleep interval
          current = compute_fingerprint(tracked)
          next if current == fingerprint

          puts "[cogni] changes detected, recompiling runtime..."
          if build_runtime(release: false, output: DEV_RUNTIME_BIN)
            terminate(runtime)
            runtime = spawn_cmd(dev_runtime_cmd(port, config_rcl))
            fingerprint = current
            puts "[cogni] runtime restarted"
          else
            STDERR.puts "[cogni] compile failed, keeping last runtime"
          end
        end
      end

      private def up(args : Array(String)) : Nil
        port = DEFAULT_PORT
        workflows_root = nil.as(String?)
        fallback_workflows_root = nil.as(String?)
        config_rcl = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("--port PORT", "Runtime port") { |v| port = v.to_i }
          parser.on("--workflows-root PATH", "Preferred workflows root path") { |v| workflows_root = v }
          parser.on("--fallback-workflows-root PATH", "Fallback workflows root path") { |v| fallback_workflows_root = v }
          parser.on("--config-rcl PATH", "RCL config path") { |v| config_rcl = v }
        end

        abort_unless_success(build_runtime(release: true, output: RUNTIME_BIN))

        command = String.build do |io|
          io << RUNTIME_BIN
          io << " --port #{port}"
          io << " --workflows-root=#{workflows_root}" if workflows_root
          io << " --fallback-workflows-root=#{fallback_workflows_root}" if fallback_workflows_root
          io << " --config-rcl=#{config_rcl}" if config_rcl
        end

        runtime = spawn_cmd(command)
        Signal::INT.trap do
          terminate(runtime)
          exit(0)
        end
        runtime.wait
      end

      private def build_runtime(release : Bool, output : String) : Bool
        release_flag = release ? "--release " : ""
        run_cmd("mkdir -p #{PROJECT_ROOT}/build && bash #{BOOTSTRAP_CRYSTAL} && crystal build #{RUNTIME_ENTRY} -D cogni_runtime_main #{release_flag}-o #{output}")
      end

      private def dev_runtime_cmd(port : Int32, config_rcl : String?) : String
        String.build do |io|
          io << DEV_RUNTIME_BIN
          io << " --port #{port}"
          io << " --config-rcl=#{config_rcl}" if config_rcl
        end
      end

      private def compute_fingerprint(paths : Array(String)) : String
        entries = [] of String
        paths.each do |path|
          next unless Dir.exists?(path)
          Dir.glob("#{path}/**/*") do |file|
            next unless File.file?(file)
            info = File.info(file)
            entries << "#{file}:#{info.size}:#{info.modification_time.to_unix_ms}"
          end
        end
        entries.sort!
        entries.join("|")
      end

      private def spawn_cmd(command : String) : Process
        Process.new("bash", args: ["-lc", command], input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end

      private def run_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-lc", command], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
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

      private def abort_unless_success(ok : Bool) : Nil
        return if ok
        exit(1)
      end

      private def terminate(process : Process) : Nil
        process.terminate
      rescue
      end
    end
  end
end
