module Ocawe
  module Workflow
    class WorkflowDefinition
      def exec(
        ref : String,
        runtime : AnyHash? = nil,
        env : AnyHash? = nil,
        workflow_root : String? = nil,
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Ocawe::RegistryApi.build_node(
          self,
          "exec",
          ref,
          runtime: runtime,
          env: env,
          workflow_root: workflow_root,
          attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      # Low-level chaining for explicit workflow nodes (used by control-flow internals).
      def step(node : WorkflowNode) : self
        append_node(node)
      end

      # Unified step entry for all built-in and external registry node types.
      def step(
        type : String,
        id : String,
        runtime : AnyHash? = nil,
        env : AnyHash? = nil,
        workflow_root : String? = nil,
        attributes : AnyHash? = nil,
        prompt : String? = nil,
        model : String? = nil,
        resume_schema : Ocawe::Workflows::DSL::Validator? = nil,
        voice_config : AnyHash? = nil,
        guardrails_config : AnyHash? = nil,
        agent_id : String? = nil,
        agent : String? = nil,
        config : AnyHash? = nil,
        reason : String? = nil,
        node_kind_name : String? = nil,
        node_kind_attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Ocawe::RegistryApi.build_node(
          self,
          type,
          id,
          runtime: runtime,
          env: env,
          workflow_root: workflow_root,
          attributes: attributes,
          prompt: prompt,
          model: model,
          resume_schema: resume_schema,
          voice_config: voice_config,
          guardrails_config: guardrails_config,
          agent_id: agent_id,
          agent: agent,
          config: config,
          reason: reason,
          node_kind_name: node_kind_name,
          node_kind_attributes: node_kind_attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end
    end
  end
end
