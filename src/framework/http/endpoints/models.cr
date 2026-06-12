module ACD
  module Kemal
    class App
      # Default model list — mirrors OpenAI /v1/models format.
      # Populated from known providers. Extend by overriding #available_models.
      private def mount_models_endpoints
        get "/v1/models" do |env|
          env.response.content_type = "application/json"
          {
            "object" => "list",
            "data" => available_models.map { |m|
              {
                "id" => m[:id],
                "object" => "model",
                "created" => m[:created],
                "owned_by" => m[:owned_by],
              }
            },
          }.to_json
        end
      end

      # Returns the list of models available through configured providers.
      # Override in subclasses or monkey-patch to add custom models.
      private def available_models : Array(NamedTuple(id: String, created: Int64, owned_by: String))
        [
          # OpenAI
          {id: "gpt-4.1", created: 174_000_000_0_i64, owned_by: "openai"},
          {id: "gpt-4.1-mini", created: 174_000_000_0_i64, owned_by: "openai"},
          {id: "gpt-4.1-nano", created: 174_000_000_0_i64, owned_by: "openai"},
          {id: "gpt-4o", created: 171_000_000_0_i64, owned_by: "openai"},
          {id: "gpt-4o-mini", created: 172_000_000_0_i64, owned_by: "openai"},
          {id: "o3", created: 173_500_000_0_i64, owned_by: "openai"},
          {id: "o4-mini", created: 173_500_000_0_i64, owned_by: "openai"},

          # ClipProxy
          {id: "cliproxyapi/qwen3-coder-plus", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/qwen3-235b-a22b", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gemma-3-27b-it", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/llama-4-maverick", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/llama-4-scout", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/deepseek-v3-0324", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/deepseek-r1-0528", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/kimi-k1.5", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gpt-4.1", created: 174_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gpt-4.1-mini", created: 174_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gpt-4.1-nano", created: 174_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gpt-4o", created: 171_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gpt-4o-mini", created: 172_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/o3", created: 173_500_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/o4-mini", created: 173_500_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/claude-sonnet-4", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/claude-opus-4", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gemini-2.5-pro", created: 175_000_000_0_i64, owned_by: "cliproxy"},
          {id: "cliproxyapi/gemini-2.5-flash", created: 175_000_000_0_i64, owned_by: "cliproxy"},

          # Gonka (decentralized inference)
          {id: "gonka/llama-4-maverick", created: 175_000_000_0_i64, owned_by: "gonka"},
          {id: "gonka/llama-4-scout", created: 175_000_000_0_i64, owned_by: "gonka"},
          {id: "gonka/qwen3-235b-a22b", created: 175_000_000_0_i64, owned_by: "gonka"},
        ]
      end
    end
  end
end
