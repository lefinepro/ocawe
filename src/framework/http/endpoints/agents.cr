module ACD
  module HTTP
    class App
      FALLBACK_CHAT_MODEL = "cliproxyapi/qwen3-coder-plus"

      private def mount_agent_endpoints
        get "/v1/agents" do |env|
          env.response.content_type = "application/json"
          {
            "agents" => agents.map { |agent|
              {
                "id" => agent[:id],
                "name" => agent[:name],
                "workflow_id" => agent[:workflow_id],
                "description" => agent[:description],
                "model" => agent[:model],
                "default_model" => agent[:default_model],
              }
            },
          }.to_json
        end

        get "/v1/agents/:agentId" do |env|
          agent_id = env.params.url["agentId"]
          agent = agent_by_id(agent_id)

          unless agent
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "agent not found: #{agent_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          {
            "id" => agent[:id],
            "name" => agent[:name],
            "workflow_id" => agent[:workflow_id],
            "description" => agent[:description],
            "model" => agent[:model],
            "default_model" => agent[:default_model],
            "prompt" => agent[:prompt],
          }.to_json
        end

        post "/v1/agents/:agentId/generate" do |env|
          agent_id = env.params.url["agentId"]
          agent = agent_by_id(agent_id)

          unless agent
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "agent not found: #{agent_id}"}}.to_json)
          end

          body = json_body(env)
          model = body["model"]?.try(&.as_s?) || agent[:model] || agent[:default_model] || FALLBACK_CHAT_MODEL
          messages = extract_chat_messages(body)
          prompt = chat_prompt_from_messages(messages, body)
          system_message = chat_system_message(messages, body)
          metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
          metadata["agent_id"] = JSON.parse(agent_id.to_json)
          metadata["workflow_id"] = JSON.parse(agent[:workflow_id].to_json)

          agent_result = nil.as(Cogni::Workflows::Declarative::AgentResult?)
          begin
            response = CogniCore::AI::Client.new.generate_text(
              model_spec: model,
              prompt: prompt,
              system: [agent[:prompt], system_message].compact.reject(&.empty?).join("\n\n"),
              metadata: metadata,
            )
            agent_result = Cogni::Workflows::Declarative::AgentResult.new(
              agent_type: "default-agent",
              content: response.text,
              provider: response.provider,
              model: response.model,
              metadata: metadata,
            )
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            next({error: {type: "generation_error", message: ex.message || "agent generation failed"}}.to_json)
          end
          result = agent_result.not_nil!

          env.response.content_type = "application/json"
          {
            "agent_id" => agent[:id],
            "workflow_id" => agent[:workflow_id],
            "agent_type" => result.agent_type,
            "provider" => result.provider,
            "model" => result.model,
            "text" => result.content,
            "metadata" => result.metadata,
          }.to_json
        end
      end

      private def extract_chat_messages(body : Cogni::Workflows::Declarative::AnyHash) : Array(NamedTuple(role: String, content: String))
        return [] of NamedTuple(role: String, content: String) unless raw = body["messages"]?
        return [] of NamedTuple(role: String, content: String) unless array = raw.as_a?

        array.compact_map do |entry|
          hash = entry.as_h?
          next unless hash
          role = hash["role"]?.try(&.as_s?) || "user"
          content_value = hash["content"]?
          next unless content_value

          content = if content_string = content_value.as_s?
                      content_string
                    elsif parts = content_value.as_a?
                      parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
                    else
                      content_value.to_json
                    end

          next if content.strip.empty?
          {role: role, content: content}
        end
      end

      private def chat_prompt_from_messages(messages : Array(NamedTuple(role: String, content: String)), body : Cogni::Workflows::Declarative::AnyHash) : String
        if input = body["input"]?.try(&.as_s?)
          return input
        end
        if prompt = body["prompt"]?.try(&.as_s?)
          return prompt
        end

        return "Hello" if messages.empty?
        messages.map { |message| "#{message[:role]}: #{message[:content]}" }.join("\n")
      end

      private def chat_system_message(messages : Array(NamedTuple(role: String, content: String)), body : Cogni::Workflows::Declarative::AnyHash) : String?
        if explicit = body["system"]?.try(&.as_s?)
          return explicit
        end
        messages.find { |message| message[:role] == "system" }.try(&.[:content])
      end
    end
  end
end
