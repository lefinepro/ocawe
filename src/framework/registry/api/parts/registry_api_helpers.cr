module Cogni
  module RegistryApi
    extend self
    private def run_voice_node(ctx : NodeContext, config : AnyHash) : AnyHash
      effective_config = (ctx.state["active_voice"]?.try(&.as_h?) || ({} of String => JSON::Any)).dup
      config.each { |k, v| effective_config[k] = v }

      voice_operator = effective_config["voice_operator"]?.try(&.as_s?) || effective_config["provider"]?.try(&.as_s?) || "default"
      speaker = effective_config["speaker"]?.try(&.as_s?)

      audio = ctx.state["audio"]?.try(&.as_s?) || ctx.input_data["audio"]?.try(&.as_s?) || ""
      text = ctx.state["text"]?.try(&.as_s?) || ctx.input_data["text"]?.try(&.as_s?) || ""

      resolved_text = if text.empty?
                        audio.empty? ? "[voice-node:no-input]" : "transcribed: #{audio}"
                      else
                        text
                      end

      payload = {
        "voice_status" => JSON.parse("ok".to_json),
        "voice_operator" => JSON.parse(voice_operator.to_json),
        "text" => JSON.parse(resolved_text.to_json),
        "audio_url" => JSON.parse("memory://voice/#{ctx.run_id}/output.wav".to_json),
      } of String => JSON::Any

      payload["speaker"] = JSON.parse(speaker.to_json) if speaker
      payload["active_voice"] = JSON.parse(effective_config.to_json) unless effective_config.empty?
      payload
    end

    private def build_agent_user_prompt(ctx : NodeContext) : String
      if input = ctx.input_data["input"]?
        if as_text = input.as_s?
          return as_text
        end
        if hash = input.as_h?
          return hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || input.to_json
        end
        return input.to_json
      end

      task = ctx.input_data["task"]?.try(&.as_s?) || ctx.state["task"]?.try(&.as_s?)
      return task if task

      prompt = ctx.input_data["prompt"]?.try(&.as_s?) || ctx.state["prompt"]?.try(&.as_s?)
      return prompt if prompt

      ctx.state.to_json
    end

    private def resolve_model(workflow : WorkflowDefinition, ctx : NodeContext, agent_model : String?) : String
      request_model = ctx.input_data["model"]?.try(&.as_s?) || ctx.state["model"]?.try(&.as_s?)
      return request_model if request_model
      return agent_model if agent_model
      ctx.state["workflow_model"]?.try(&.as_s?) || workflow.default_model || "openai/gpt-4.1-mini"
    end
  end
end
