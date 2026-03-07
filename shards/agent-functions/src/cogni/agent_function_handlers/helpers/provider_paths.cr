module Cogni
  module AgentFunctionHandlers
    extend self

    private def home_dir : String
      ENV["HOME"]? || "/tmp"
    end

    private def provider_native_credentials_path(provider : String) : String?
      home = home_dir
      case provider
      when "codex" then "#{home}/.codex/auth.json"
      when "claude_code" then "#{home}/.claude/credentials.json"
      when "opencode" then "#{home}/.config/opencode/auth.json"
      when "qwen" then "#{home}/.qwen/credentials.json"
      else
        nil
      end
    end

    private def provider_native_config_path(provider : String) : String?
      home = home_dir
      case provider
      when "codex" then "#{home}/.codex/config.toml"
      when "claude_code" then "#{home}/.claude/settings.json"
      when "opencode" then "#{home}/.config/opencode/config.json"
      when "qwen" then "#{home}/.qwen/config.json"
      else
        nil
      end
    end

    private def provider_fallback_credentials_path(provider : String) : String
      "#{home_dir}/.config/cogni/providers/#{provider}/credentials.json"
    end

    private def provider_fallback_config_path(provider : String) : String
      "#{home_dir}/.config/cogni/providers/#{provider}/config.json"
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
  end
end
