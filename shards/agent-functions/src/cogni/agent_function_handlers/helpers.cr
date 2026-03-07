module Cogni
  module AgentFunctionHandlers
    extend self

    private def provider_default_bin(provider : String) : String
      case provider
      when "codex"
        "codex"
      when "claude_code"
        "claude"
      when "opencode"
        "opencode"
      when "qwen"
        "qwen"
      else
        provider
      end
    end

    private def provider_native_credentials_path(provider : String) : String?
      home = home_dir
      case provider
      when "codex"
        "#{home}/.codex/auth.json"
      when "claude_code"
        "#{home}/.claude/credentials.json"
      when "opencode"
        "#{home}/.config/opencode/auth.json"
      when "qwen"
        "#{home}/.qwen/credentials.json"
      else
        nil
      end
    end

    private def provider_native_config_path(provider : String) : String?
      home = home_dir
      case provider
      when "codex"
        "#{home}/.codex/config.toml"
      when "claude_code"
        "#{home}/.claude/settings.json"
      when "opencode"
        "#{home}/.config/opencode/config.json"
      when "qwen"
        "#{home}/.qwen/config.json"
      else
        nil
      end
    end

    private def home_dir : String
      ENV["HOME"]? || "/tmp"
    end

    private def provider_fallback_credentials_path(provider : String) : String
      "#{home_dir}/.config/cogni/providers/#{provider}/credentials.json"
    end

    private def provider_fallback_config_path(provider : String) : String
      "#{home_dir}/.config/cogni/providers/#{provider}/config.json"
    end

    private def command_exists?(command : String) : Bool
      executable = extract_executable(command)
      return false if executable.empty?
      return File.exists?(executable) if executable.includes?("/")

      status = Process.run("bash", args: ["-lc", "command -v #{shell_escape(executable)} >/dev/null 2>&1"])
      status.success?
    rescue
      false
    end

    private def extract_executable(command : String) : String
      command.split(/\s+/, remove_empty: true).first?.to_s
    end

    private def provider_default_install_commands(provider : String) : Array(String)
      case provider
      when "codex"
        ["npm install -g @openai/codex"]
      when "claude_code"
        ["npm install -g @anthropic-ai/claude-code"]
      when "opencode"
        ["npm install -g @opencode-ai/cli", "npm install -g opencode"]
      when "qwen"
        ["pip install -U qwen-code", "npm install -g @qwen-code/cli"]
      else
        [] of String
      end
    end

    private def ensure_provider_cli_available(
      ctx : Cogni::Workflow::NodeContext,
      provider : String,
      command : String
    ) : String?
      return nil if command_exists?(command)

      policy = resolve_string_param(ctx, "install_policy", env_keys: ["COGNI_AGENT_INSTALL_POLICY"], default: "on_demand").to_s.downcase
      return "#{provider} binary not found and install_policy=never" if policy == "never"

      custom = resolve_string_param(
        ctx,
        "installer_command",
        env_keys: ["#{provider.upcase}_INSTALL_COMMAND", "COGNI_#{provider.upcase}_INSTALL_COMMAND"]
      )
      commands = [] of String
      commands << custom.not_nil! if custom && !custom.empty?
      commands.concat(provider_default_install_commands(provider))
      commands.uniq!

      return "no installer command configured for #{provider}" if commands.empty?

      error_messages = [] of String
      commands.each do |installer|
        status, stdout, stderr = run_shell(installer)
        if status.success? && command_exists?(command)
          return nil
        end
        details = stderr.strip.empty? ? stdout.strip : stderr.strip
        error_messages << "#{installer}: #{details.empty? ? "failed" : details}"
      end

      "failed to install #{provider}: #{error_messages.join(" | ")}"
    end

    private def run_shell(command : String) : Tuple(Process::Status, String, String)
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run("bash", args: ["-lc", command], output: stdout, error: stderr)
      {status, stdout.to_s, stderr.to_s}
    end

    private def shell_escape(value : String) : String
      "'" + value.gsub("'", %q('"'"')) + "'"
    end

    private def resolve_provider_credentials_path(ctx : Cogni::Workflow::NodeContext, provider : String) : String
      env_keys = ["#{provider.upcase}_PATH_TO_CREDENTIALS", "COGNI_#{provider.upcase}_PATH_TO_CREDENTIALS"]
      path = case provider
             when "codex"
               resolve_string_param(ctx, "path_to_credentials_codex", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_credentials", env_keys: env_keys)
             when "claude_code"
               resolve_string_param(ctx, "path_to_credentials_claude_code", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_credentials_claude", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_credentials", env_keys: env_keys)
             when "opencode"
               resolve_string_param(ctx, "path_to_credentials_opencode", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_credentials", env_keys: env_keys)
             when "qwen"
               resolve_string_param(ctx, "path_to_credentials_qwen", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_credentials", env_keys: env_keys)
             else
               resolve_string_param(ctx, "path_to_credentials", env_keys: env_keys)
             end

      resolved = path || provider_native_credentials_path(provider) || provider_fallback_credentials_path(provider)
      expand_home(resolved)
    end

    private def resolve_provider_config_path(ctx : Cogni::Workflow::NodeContext, provider : String) : String
      env_keys = ["#{provider.upcase}_PATH_TO_CONFIG", "COGNI_#{provider.upcase}_PATH_TO_CONFIG"]
      path = case provider
             when "codex"
               resolve_string_param(ctx, "path_to_config_codex", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_config", env_keys: env_keys)
             when "claude_code"
               resolve_string_param(ctx, "path_to_config_claude_code", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_config_claude", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_config", env_keys: env_keys)
             when "opencode"
               resolve_string_param(ctx, "path_to_config_opencode", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_config", env_keys: env_keys)
             when "qwen"
               resolve_string_param(ctx, "path_to_config_qwen", env_keys: env_keys) ||
                 resolve_string_param(ctx, "path_to_config", env_keys: env_keys)
             else
               resolve_string_param(ctx, "path_to_config", env_keys: env_keys)
             end

      resolved = path || provider_native_config_path(provider) || provider_fallback_config_path(provider)
      expand_home(resolved)
    end

    private def expand_home(path : String) : String
      return path unless path.starts_with?("~/")
      "#{home_dir}/#{path[2..]}"
    end

    private def ensure_parent_dir(path : String) : Nil
      parent = File.dirname(path)
      return if parent.empty? || parent == "."
      Dir.mkdir_p(parent)
    end

    private def provider_env(ctx : Cogni::Workflow::NodeContext, provider : String) : Hash(String, String)
      credentials_path = resolve_provider_credentials_path(ctx, provider)
      config_path = resolve_provider_config_path(ctx, provider)
      ensure_parent_dir(credentials_path)
      ensure_parent_dir(config_path)

      env = {} of String => String
      env["COGNI_PATH_TO_CREDENTIALS"] = credentials_path
      env["COGNI_PATH_TO_CONFIG"] = config_path

      case provider
      when "codex"
        env["CODEX_PATH_TO_CREDENTIALS"] = credentials_path
        env["CODEX_PATH_TO_CONFIG"] = config_path
        env["PATH_TO_CONFIG_CODEX"] = config_path
      when "claude_code"
        env["CLAUDE_CODE_PATH_TO_CREDENTIALS"] = credentials_path
        env["CLAUDE_CODE_PATH_TO_CONFIG"] = config_path
      when "opencode"
        env["OPENCODE_PATH_TO_CREDENTIALS"] = credentials_path
        env["OPENCODE_PATH_TO_CONFIG"] = config_path
      when "qwen"
        env["QWEN_PATH_TO_CREDENTIALS"] = credentials_path
        env["QWEN_PATH_TO_CONFIG"] = config_path
      end

      env
    end

    private def run_agent_cli(
      command : String,
      args : Array(String),
      prompt : String,
      env : Hash(String, String) = {} of String => String
    ) : Tuple(Process::Status, String, String, Array(String))
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      input = IO::Memory.new(prompt)
      resolved_args = args.map { |arg| arg == "{prompt}" ? prompt : arg }

      status = if resolved_args.includes?(prompt)
                 Process.run(command, args: resolved_args, output: stdout, error: stderr, env: env)
               elsif resolved_args.empty?
                 Process.run(command, input: input, output: stdout, error: stderr, env: env)
               else
                 Process.run(command, args: resolved_args, input: input, output: stdout, error: stderr, env: env)
               end

      {status, stdout.to_s, stderr.to_s, resolved_args}
    end

    private def extract_input_text(input : JSON::Any?) : String
      return "" unless input
      if text = input.as_s?
        return text
      end
      if hash = input.as_h?
        return hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || input.to_json
      end
      input.to_json
    end

    private def join_url(base_url : String, path : String) : String
      base = base_url.ends_with?("/") ? base_url[0, base_url.size - 1] : base_url
      "#{base}#{path}"
    end

    private def has_model_flag?(args : Array(String)) : Bool
      args.any? { |arg| arg == "--model" || arg == "-m" || arg.starts_with?("--model=") }
    end

    private def resolve_string_param(
      ctx : Cogni::Workflow::NodeContext,
      key : String,
      env_keys : Array(String) = [] of String,
      default : String? = nil
    ) : String?
      if value = workflow_param_from_ctx(ctx, key)
        if string = value.as_s?
          return string
        end
      end

      if value = input_param_from_ctx(ctx, key)
        if string = value.as_s?
          return string
        end
      end

      env_keys.each do |env_key|
        env_val = ENV[env_key]?
        return env_val if env_val && !env_val.empty?
      end

      default
    end

    private def resolve_string_array_param(
      ctx : Cogni::Workflow::NodeContext,
      key : String,
      env_keys : Array(String) = [] of String
    ) : Array(String)
      env_keys.each do |env_key|
        env_val = ENV[env_key]?
        next unless env_val && !env_val.empty?
        return env_val.split(/[,\s]+/).map(&.strip).reject(&.empty?)
      end

      if value = workflow_param_from_ctx(ctx, key)
        return json_to_string_array(value)
      end

      if value = input_param_from_ctx(ctx, key)
        return json_to_string_array(value)
      end

      [] of String
    end

    private def workflow_param_from_ctx(ctx : Cogni::Workflow::NodeContext, key : String) : JSON::Any?
      ctx.input_data[key]?
    end

    private def input_param_from_ctx(ctx : Cogni::Workflow::NodeContext, key : String) : JSON::Any?
      input_payload = ctx.input_data["input"]?.try(&.as_h?)
      return nil unless input_payload
      input_payload[key]?
    end

    private def json_to_string_array(value : JSON::Any) : Array(String)
      if entries = value.as_a?
        return entries.compact_map(&.as_s?)
      end
      if single = value.as_s?
        return [single]
      end
      [] of String
    end

    private def parse_session_id(body : String) : String?
      parsed = JSON.parse(body).as_h?
      return nil unless parsed
      parsed["id"]?.try(&.as_s?) ||
        parsed["sessionID"]?.try(&.as_s?) ||
        parsed["session_id"]?.try(&.as_s?) ||
        parsed["session"]?.try(&.as_h?).try(&.["id"]?).try(&.as_s?)
    rescue
      nil
    end

    private def parse_opencode_message_content(body : String) : String?
      parsed = JSON.parse(body).as_h?
      return nil unless parsed
      content = parsed["content"]?.try(&.as_s?)
      return content if content
      text = parsed["text"]?.try(&.as_s?)
      return text if text

      parts = parsed["parts"]?.try(&.as_a?)
      if parts
        joined = parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
        return joined unless joined.empty?
      end

      message = parsed["message"]?.try(&.as_h?)
      if message
        direct = message["content"]?.try(&.as_s?) || message["text"]?.try(&.as_s?)
        return direct if direct
        msg_parts = message["parts"]?.try(&.as_a?)
        if msg_parts
          joined = msg_parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
          return joined unless joined.empty?
        end
      end
      nil
    rescue
      nil
    end

    private def any(value) : JSON::Any
      JSON.parse(value.to_json)
    end
  end
end
