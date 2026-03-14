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
        "voice_status"   => JSON.parse("ok".to_json),
        "voice_operator" => JSON.parse(voice_operator.to_json),
        "text"           => JSON.parse(resolved_text.to_json),
        "audio_url"      => JSON.parse("memory://voice/#{ctx.run_id}/output.wav".to_json),
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

    private def parse_agent_json_payload(content : String) : AnyHash?
      normalized = content.strip
      return nil if normalized.empty?

      if normalized.starts_with?("```")
        lines = normalized.lines
        if lines.size >= 2 && lines.last.strip == "```"
          normalized = lines[1...-1].join.strip
        end
      end

      JSON.parse(normalized).as_h?
    rescue
      nil
    end

    private def run_forgefed_subscribe_node(ctx : NodeContext, parameters : AnyHash) : AnyHash
      name = first_non_empty(
        parameters["name"]?.try(&.as_s?),
        parameters["target"]?.try(&.as_s?),
        parameters["remote_actor"]?.try(&.as_s?),
        ctx.input_data["name"]?.try(&.as_s?),
        ctx.input_data["target"]?.try(&.as_s?),
        ctx.input_data["remote_actor"]?.try(&.as_s?),
        ctx.state["name"]?.try(&.as_s?),
        ctx.state["target"]?.try(&.as_s?),
        ctx.state["remote_actor"]?.try(&.as_s?),
      )
      raise "forgefed_subscribe requires name or remote_actor" if name.empty?

      settings = load_registry_settings(parameters["config_rcl"]?.try(&.as_s?))
      store = build_registry_federation_store(settings.federation)
      actor_document = parameters["actor_document"]?.try(&.as_h?)
      record = Cogni::Federation::Subscriptions.ensure(settings, store, name, actor_document: actor_document)

      {
        "subscription_name"   => json_value(name),
        "subscription_status" => json_value(record["status"]?.try(&.as_s?) || "active"),
        "remote_actor"        => json_value(record["remote_actor"]?.try(&.as_s?) || ""),
        "remote_outbox"       => json_value(record["remote_outbox"]?.try(&.as_s?) || ""),
        "remote_inbox"        => json_value(record["remote_inbox"]?.try(&.as_s?) || ""),
        "queue"               => json_value(record["queue"]?.try(&.as_s?) || ""),
        "follow_record"       => JSON.parse(record.to_json),
      } of String => JSON::Any
    end

    private def load_registry_settings(config_rcl : String?) : Cogni::Config::Settings
      default_settings = Cogni::Config::Settings.default
      explicit = first_non_empty(config_rcl, ENV["COGNI_CONFIG_RCL"]?)
      return default_settings if explicit.empty?
      CogniCore::Utils::ConfigParser.load_settings(default_settings, rcl_path: explicit)
    end

    private def build_registry_federation_store(config : Cogni::Config::FederationSettings) : Cogni::Federation::Store::Base
      case config.adapter.strip.downcase
      when "", "memory"
        Cogni::Federation::Store::Memory.new
      when "sqlite"
        Cogni::Federation::Store::SQLite.new(config.sqlite_path)
      else
        raise "unsupported federation adapter: #{config.adapter}"
      end
    end

    private def first_non_empty(*values : String?) : String
      values.each do |value|
        next unless value
        stripped = value.strip
        return stripped unless stripped.empty?
      end
      ""
    end

    private def json_value(value) : JSON::Any
      JSON.parse(value.to_json)
    end
  end
end
