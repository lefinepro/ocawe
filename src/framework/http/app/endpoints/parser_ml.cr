module ACD
  module Kemal
    class App
      private ML_NODE_TYPES = Set{"train", "infer", "embed", "eval"}

      private def parse_model_declaration(ctx : WorkflowParserContext, model_id : String, tail : String) : Nil
        attributes = parse_line_attributes(tail, ctx.workflow_file, "model #{model_id}")
        runtime = attributes["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
        description = parse_optional_string(attributes["description"]?)
        task = parse_optional_string(attributes["task"]?)
        base_model = parse_optional_string(attributes["base_model"]?)
        metadata = extract_attributes(attributes, Set{"runtime", "description", "task", "base_model"}, ctx.workflow_file)
        ctx.ml_service.register_from_dsl(
          model_id,
          source_file: ctx.workflow_file,
          description: description,
          task: task,
          base_model: base_model,
          runtime: runtime,
          metadata: metadata,
        )
      end

      private def parse_ml_node(ctx : WorkflowParserContext, kind : String, id : String, tail : String) : Nil
        attributes = parse_line_attributes(tail, ctx.workflow_file, "#{kind} #{id}")
        config = extract_attributes(attributes, Set(String).new, ctx.workflow_file) || ({} of String => JSON::Any)
        ctx.workflow.step(kind, id, attributes: config)
      end

      private def ml_node_type?(value : String) : Bool
        ML_NODE_TYPES.includes?(value)
      end
    end
  end
end
