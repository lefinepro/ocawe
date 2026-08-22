module ACD
  module Kemal
    class App
      # Compatibility endpoint used by providers that expose their catalogue
      # pricing at /api/pricing rather than through /v1/models.
      private def mount_pricing_endpoints
        get "/api/pricing" do |env|
          env.response.content_type = "application/json"
          rotator_pricing_response
        end
        post "/api/pricing" do |env|
          env.response.content_type = "application/json"
          rotator_pricing_response
        end
      end

      private def rotator_pricing_response : String
        ctx = Ocawe::Workflow::NodeContext.new(
          workflow_id: "api:pricing",
          run_id: "pricing_#{Random::Secure.hex(8)}",
          node_id: "rotator_model_inventory",
          input_data: {} of String => JSON::Any,
          state: {} of String => JSON::Any,
        )
        inventory = Ocawe::RegistryApi.call_function("rotator_model_inventory", ctx)
        inventory_models = inventory["models"]?.try(&.as_a?) || [] of JSON::Any
        models = inventory_models.compact_map do |model|
          model_hash = model.as_h?
          next unless model_hash
          model_id = model_hash["model"]?.try(&.as_s?) || model_hash["id"]?.try(&.as_s?)
          next if model_id.nil? || model_id.empty?

          input = pricing_value(model_hash["input_price_per_million"]?)
          output = pricing_value(model_hash["output_price_per_million"]?)
          price = input || output
          next unless price

          payload = {
            "model_id" => JSON.parse(model_id.to_json),
            # The provider compatibility contract uses USD per token.
            "usd_per_token" => JSON.parse((price / 1_000_000.0).to_json),
          } of String => JSON::Any
          payload["input_usd_per_token"] = JSON.parse((input / 1_000_000.0).to_json) if input
          payload["output_usd_per_token"] = JSON.parse((output / 1_000_000.0).to_json) if output
          payload
        end

        {"models" => JSON.parse(models.to_json)}.to_json
      rescue ex
        {"models" => JSON.parse("[]"), "error" => JSON.parse((ex.message || ex.class.name).to_json)}.to_json
      end

      private def pricing_value(value : JSON::Any?) : Float64?
        return unless value
        value.as_f? || value.as_i?.try(&.to_f) || value.as_s?.try(&.to_f?)
      end
    end
  end
end
