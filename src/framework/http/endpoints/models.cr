module ACD
  module Kemal
    class App
      private def mount_models_endpoints
        get "/v1/models" do |env|
          env.response.content_type = "application/json"
          {
            "data" => available_models.map { |m|
              {
                "id"               => m[:id],
                "name"             => m[:name],
                "description"      => m[:description],
                "context_length"   => m[:context_length],
                "pricing"          => m[:pricing],
                "created"          => m[:created],
                "architecture"     => m[:architecture],
                "top_provider"     => m[:top_provider],
                "per_request_limits" => m[:per_request_limits],
              }
            },
          }.to_json
        end
      end

      private def available_models : Array(NamedTuple(
        id: String,
        name: String,
        description: String,
        context_length: Int32?,
        pricing: Hash(String, String),
        created: Int64,
        architecture: Hash(String, JSON::Any),
        top_provider: Hash(String, JSON::Any),
        per_request_limits: Hash(String, Int32)?,
      ))
        models = [] of NamedTuple(
          id: String,
          name: String,
          description: String,
          context_length: Int32?,
          pricing: Hash(String, String),
          created: Int64,
          architecture: Hash(String, JSON::Any),
          top_provider: Hash(String, JSON::Any),
          per_request_limits: Hash(String, Int32)?,
        )

        now = Time.utc.to_unix

        # Agents
        agents.each do |a|
          models << {
            id:               a[:id],
            name:             a[:name],
            description:      "Agent: #{a[:description]}",
            context_length:   128000,
            pricing:          {"prompt" => "0", "completion" => "0", "request" => "0"},
            created:          now,
            architecture:     {
              "modality"          => JSON.parse("\"text->text\""),
              "tokenizer"         => JSON.parse("\"Other\""),
              "instruct_type"     => JSON.parse("null"),
              "input_modalities"  => JSON.parse("[\"text\"]"),
              "output_modalities" => JSON.parse("[\"text\"]"),
            } of String => JSON::Any,
            top_provider:     {
              "is_moderated"         => JSON.parse("false"),
              "context_length"       => JSON.parse("128000"),
              "max_completion_tokens" => JSON.parse("16384"),
            } of String => JSON::Any,
            per_request_limits: {"prompt_tokens" => 128000, "completion_tokens" => 16384},
          }
        end

        # Workflows
        workflows.each do |w|
          models << {
            id:               "workflow/#{w[:id]}",
            name:             w[:name],
            description:      "Workflow: #{w[:description]}",
            context_length:   128000,
            pricing:          {"prompt" => "0", "completion" => "0", "request" => "0"},
            created:          now,
            architecture:     {
              "modality"          => JSON.parse("\"text->text\""),
              "tokenizer"         => JSON.parse("\"Other\""),
              "instruct_type"     => JSON.parse("null"),
              "input_modalities"  => JSON.parse("[\"text\"]"),
              "output_modalities" => JSON.parse("[\"text\"]"),
            } of String => JSON::Any,
            top_provider:     {
              "is_moderated"         => JSON.parse("false"),
              "context_length"       => JSON.parse("128000"),
              "max_completion_tokens" => JSON.parse("16384"),
            } of String => JSON::Any,
            per_request_limits: {"prompt_tokens" => 128000, "completion_tokens" => 16384},
          }
        end

        # Skills
        skills.each do |s|
          models << {
            id:               s[:id],
            name:             s[:name],
            description:      "Skill: #{s[:description]}",
            context_length:   128000,
            pricing:          {"prompt" => "0", "completion" => "0", "request" => "0"},
            created:          now,
            architecture:     {
              "modality"          => JSON.parse("\"text->text\""),
              "tokenizer"         => JSON.parse("\"Other\""),
              "instruct_type"     => JSON.parse("null"),
              "input_modalities"  => JSON.parse("[\"text\"]"),
              "output_modalities" => JSON.parse("[\"text\"]"),
            } of String => JSON::Any,
            top_provider:     {
              "is_moderated"         => JSON.parse("false"),
              "context_length"       => JSON.parse("128000"),
              "max_completion_tokens" => JSON.parse("16384"),
            } of String => JSON::Any,
            per_request_limits: {"prompt_tokens" => 128000, "completion_tokens" => 16384},
          }
        end

        # Tools
        tools.each do |t|
          models << {
            id:               "tool/#{t[:id]}",
            name:             t[:id],
            description:      "Tool: #{t[:workflow_id]}",
            context_length:   128000,
            pricing:          {"prompt" => "0", "completion" => "0", "request" => "0"},
            created:          now,
            architecture:     {
              "modality"          => JSON.parse("\"text->text\""),
              "tokenizer"         => JSON.parse("\"Other\""),
              "instruct_type"     => JSON.parse("null"),
              "input_modalities"  => JSON.parse("[\"text\"]"),
              "output_modalities" => JSON.parse("[\"text\"]"),
            } of String => JSON::Any,
            top_provider:     {
              "is_moderated"         => JSON.parse("false"),
              "context_length"       => JSON.parse("128000"),
              "max_completion_tokens" => JSON.parse("16384"),
            } of String => JSON::Any,
            per_request_limits: {"prompt_tokens" => 128000, "completion_tokens" => 16384},
          }
        end

        models
      end
    end
  end
end
