module Cogni
  module AgentFunctionHandlers
    extend self

    private def provider_default_bin(provider : String) : String
      case provider
      when "codex"       then "codex"
      when "claude_code" then "claude"
      when "opencode"    then "opencode"
      when "qwen"        then "qwen"
      else
        provider
      end
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

    private def ensure_npm_command : String
      "command -v npm >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends nodejs npm ca-certificates && rm -rf /var/lib/apt/lists/*)"
    end

    private def ensure_pip3_command : String
      "command -v pip3 >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ca-certificates && rm -rf /var/lib/apt/lists/*)"
    end

    private def provider_default_install_commands(provider : String) : Array(String)
      case provider
      when "codex"
        [
          "command -v codex >/dev/null 2>&1 || (#{ensure_npm_command}; npm install -g @openai/codex)",
        ]
      when "claude_code"
        [
          "command -v claude >/dev/null 2>&1 || (#{ensure_npm_command}; npm install -g @anthropic-ai/claude-code)",
        ]
      when "opencode"
        [
          "command -v opencode >/dev/null 2>&1 || (#{ensure_npm_command}; npm install -g @opencode-ai/cli || npm install -g opencode)",
        ]
      when "qwen"
        [
          "command -v qwen >/dev/null 2>&1 || (#{ensure_pip3_command}; pip3 install -U qwen-code || (#{ensure_npm_command}; npm install -g @qwen-code/cli))",
        ]
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
  end
end
