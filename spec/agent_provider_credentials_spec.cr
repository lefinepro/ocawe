require "./spec_helper"

describe "Ocawe::AgentFunctionHandlers provider credentials forwarding" do
  it "builds provider env for codex, claude_code, opencode and qwen" do
    home = ENV["HOME"]? || "/tmp"

    codex_env = Ocawe::AgentFunctionHandlers.test_provider_env(
      "codex",
      {
        "path_to_credentials_codex" => json_str("~/spec/codex/auth.json"),
        "path_to_config_codex"      => json_str("~/spec/codex/config.toml"),
      } of String => JSON::Any,
    )
    codex_env["COGNI_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/codex/auth.json")
    codex_env["COGNI_PATH_TO_CONFIG"].should eq("#{home}/spec/codex/config.toml")
    codex_env["CODEX_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/codex/auth.json")
    codex_env["CODEX_PATH_TO_CONFIG"].should eq("#{home}/spec/codex/config.toml")

    claude_env = Ocawe::AgentFunctionHandlers.test_provider_env(
      "claude_code",
      {
        "path_to_credentials_claude_code" => json_str("~/spec/claude/credentials.json"),
        "path_to_config_claude_code"      => json_str("~/spec/claude/settings.json"),
      } of String => JSON::Any,
    )
    claude_env["COGNI_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/claude/credentials.json")
    claude_env["COGNI_PATH_TO_CONFIG"].should eq("#{home}/spec/claude/settings.json")
    claude_env["CLAUDE_CODE_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/claude/credentials.json")
    claude_env["CLAUDE_CODE_PATH_TO_CONFIG"].should eq("#{home}/spec/claude/settings.json")

    opencode_env = Ocawe::AgentFunctionHandlers.test_provider_env(
      "opencode",
      {
        "path_to_credentials_opencode" => json_str("~/spec/opencode/credentials.json"),
        "path_to_config_opencode"      => json_str("~/spec/opencode/config.json"),
      } of String => JSON::Any,
    )
    opencode_env["COGNI_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/opencode/credentials.json")
    opencode_env["COGNI_PATH_TO_CONFIG"].should eq("#{home}/spec/opencode/config.json")
    opencode_env["OPENCODE_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/opencode/credentials.json")
    opencode_env["OPENCODE_PATH_TO_CONFIG"].should eq("#{home}/spec/opencode/config.json")

    qwen_env = Ocawe::AgentFunctionHandlers.test_provider_env(
      "qwen",
      {
        "path_to_credentials_qwen" => json_str("~/spec/qwen/credentials.json"),
        "path_to_config_qwen"      => json_str("~/spec/qwen/config.json"),
      } of String => JSON::Any,
    )
    qwen_env["COGNI_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/qwen/credentials.json")
    qwen_env["COGNI_PATH_TO_CONFIG"].should eq("#{home}/spec/qwen/config.json")
    qwen_env["QWEN_PATH_TO_CREDENTIALS"].should eq("#{home}/spec/qwen/credentials.json")
    qwen_env["QWEN_PATH_TO_CONFIG"].should eq("#{home}/spec/qwen/config.json")
  end
end
