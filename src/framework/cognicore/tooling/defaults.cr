require "json"
require "../ai/client"

module CogniCore
  module Tooling
    def self.tool_ai_generate_text(ctx : Workflow::NodeContext) : Workflow::AnyHash
      input = ctx.state
      model = input["model"]?.try(&.as_s?) || input["workflow_model"]?.try(&.as_s?) || "openai/gpt-4.1-mini"
      prompt = input["prompt"]?.try(&.as_s?) || input["task"]?.try(&.as_s?) || ""
      system = input["system"]?.try(&.as_s?)

      response = AI::Client.new.generate_text(
        model_spec: model,
        prompt: prompt,
        system: system,
        metadata: {
          "workflow_id" => any(ctx.workflow_id),
          "run_id" => any(ctx.run_id),
          "node_id" => any(ctx.node_id),
        },
      )

      {
        "tool" => any("ai-generate-text"),
        "provider" => any(response.provider),
        "model" => any("#{response.provider}/#{response.model}"),
        "text" => any(response.text),
      }
    end

    def self.tool_create_sandbox(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("create-sandbox")
    end

    def self.tool_attach_sandbox(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("attach-sandbox")
    end

    def self.tool_opencode_coding(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("opencode-coding")
    end

    def self.tool_create_artifact(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("create-artifact")
    end

    def self.tool_clear_sandbox(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("clear-sandbox")
    end

    def self.tool_compress_tarball(_ctx : Workflow::NodeContext) : Workflow::AnyHash
      simple_ok("compress-tarball")
    end

    private def self.simple_ok(tool_name : String) : Workflow::AnyHash
      {
        "tool" => any(tool_name),
        "status" => any("ok"),
      }
    end

    private def self.any(value) : JSON::Any
      JSON.parse(value.to_json)
    end
  end
end
