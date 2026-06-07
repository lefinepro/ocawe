module Ocawe
  module AgentFunctionHandlers
    extend self

    private def apply_agent_prompt_contracts(
      ctx : Ocawe::Workflow::NodeContext,
      prompt : String
    ) : String
      merged = apply_output_path_prompt_contract(ctx, prompt)
      apply_forgefed_merge_prompt_contract(ctx, merged)
    end

    private def apply_output_path_prompt_contract(
      ctx : Ocawe::Workflow::NodeContext,
      prompt : String
    ) : String
      explicit_path = output_path_from_context(ctx)
      path_line = explicit_path.empty? ? "- Current task path is not set; if provided, treat `path` as mandatory target." : "- Current task path: #{explicit_path}"

      instruction = <<-TEXT
FILE OUTPUT CONTRACT (MANDATORY)
- If task input includes `path`, write/update output directly at that exact path.
- Never create a separate output file for the final result.
- Do not ask the user to copy content manually.
#{path_line}
END CONTRACT
TEXT

      return instruction if prompt.empty?
      "#{instruction}\n\n#{prompt}"
    end

    private def apply_forgefed_merge_prompt_contract(
      ctx : Ocawe::Workflow::NodeContext,
      prompt : String
    ) : String
      return prompt unless federation_merge_contract_required?(ctx)

      instruction = <<-TEXT
FORGEFED MERGE OUTPUT CONTRACT (MANDATORY)
- Return exactly one JSON object and nothing else.
- No markdown fences, no explanations, no prose.
- JSON must be a ForgeFed Offer activity in this shape:
  {
    "type": "Offer",
    "object": {
      "type": "Ticket",
      "summary": "...",
      "source": {"mediaType": "text/markdown; variant=Commonmark", "content": "..."},
      "content": "<p>...</p>",
      "mediaType": "text/html",
      "attachment": {
        "type": "Offer",
        "object": {
          "type": "OrderedCollection",
          "totalItems": 1,
          "items": [
            {"type": "Patch", "mediaType": "application/x-git-patch", "content": "..."}
          ]
        }
      }
    }
  }
- Include at least one Patch item with non-empty content.
- Put all merge result data inside JSON fields only.
END CONTRACT
TEXT

      return instruction if prompt.empty?
      "#{instruction}\n\nTASK:\n#{prompt}"
    end

    private def output_path_from_context(ctx : Ocawe::Workflow::NodeContext) : String
      %w(path output_path target_path file_path).each do |key|
        value = context_string_param(ctx, key)
        return value unless value.empty?
      end

      ""
    end

    private def federation_merge_contract_required?(ctx : Ocawe::Workflow::NodeContext) : Bool
      api = context_string_param(ctx, "api").downcase
      return false unless api == "federation"

      activity = context_string_param(ctx, "activity").downcase
      activity == "merge" || activity == "mergerequest"
    end

    private def context_string_param(ctx : Ocawe::Workflow::NodeContext, key : String) : String
      top_level = ctx.input_data[key]?.try(&.as_s?)
      return top_level.not_nil! if top_level && !top_level.empty?

      input_payload = ctx.input_data["input"]?.try(&.as_h?)
      if input_payload
        input_val = input_payload[key]?.try(&.as_s?)
        return input_val.not_nil! if input_val && !input_val.empty?
      end

      ticket_payload = ctx.input_data["ticket"]?.try(&.as_h?)
      if ticket_payload
        ticket_val = ticket_payload[key]?.try(&.as_s?)
        return ticket_val.not_nil! if ticket_val && !ticket_val.empty?
      end

      state_top_level = ctx.state[key]?.try(&.as_s?)
      return state_top_level.not_nil! if state_top_level && !state_top_level.empty?

      state_input_payload = ctx.state["input"]?.try(&.as_h?)
      if state_input_payload
        state_input_val = state_input_payload[key]?.try(&.as_s?)
        return state_input_val.not_nil! if state_input_val && !state_input_val.empty?
      end

      state_ticket_payload = ctx.state["ticket"]?.try(&.as_h?)
      if state_ticket_payload
        state_ticket_val = state_ticket_payload[key]?.try(&.as_s?)
        return state_ticket_val.not_nil! if state_ticket_val && !state_ticket_val.empty?
      end

      ""
    end
  end
end
