module Cogni
  module Workflow
    class WorkflowDefinition
      def run(
        ref : String,
        runtime : AnyHash? = nil,
        env : AnyHash? = nil,
        workflow_root : String? = nil,
        params : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "run",
          ref,
          runtime: runtime,
          env: env,
          workflow_root: workflow_root,
          params: params,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_codex(
        id : String = "agent_codex",
        params : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "agent_codex",
          id,
          params: params,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_cliproxy(
        id : String = "agent_cliproxy",
        params : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "agent_cliproxy",
          id,
          params: params,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_opencode(
        id : String = "agent_opencode",
        params : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "agent_opencode",
          id,
          params: params,
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
        params : AnyHash? = nil,
        prompt : String? = nil,
        model : String? = nil,
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        voice_config : AnyHash? = nil,
        guardrails_config : AnyHash? = nil,
        agent_id : String? = nil,
        agent : String? = nil,
        config : AnyHash? = nil,
        reason : String? = nil,
        node_kind_name : String? = nil,
        node_kind_parameters : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          type,
          id,
          runtime: runtime,
          env: env,
          workflow_root: workflow_root,
          params: params,
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
          node_kind_parameters: node_kind_parameters,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end
    end
  end
end
