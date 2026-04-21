module Cogni
  module Workflow
    class WorkflowDefinition
      def exec(
        ref : String,
        runtime : AnyHash? = nil,
        env : AnyHash? = nil,
        workflow_root : String? = nil,
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
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

      def agent_codex(
        id : String = "agent_codex",
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          id,
          node_kind_name: "agent_codex",
          node_kind_attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_cliproxy(
        id : String = "agent_cliproxy",
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          id,
          node_kind_name: "agent_cliproxy",
          node_kind_attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_opencode(
        id : String = "agent_opencode",
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          id,
          node_kind_name: "agent_opencode",
          node_kind_attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_claude_code(
        id : String = "agent_claude_code",
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          id,
          node_kind_name: "agent_claude_code",
          node_kind_attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def agent_qwen(
        id : String = "agent_qwen",
        attributes : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          id,
          node_kind_name: "agent_qwen",
          node_kind_attributes: attributes,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def train(id : String, attributes : AnyHash? = nil) : self
        append_node(Cogni::RegistryApi.build_node(self, "train", id, attributes: attributes))
      end

      def infer(id : String, attributes : AnyHash? = nil) : self
        append_node(Cogni::RegistryApi.build_node(self, "infer", id, attributes: attributes))
      end

      def embed(id : String, attributes : AnyHash? = nil) : self
        append_node(Cogni::RegistryApi.build_node(self, "embed", id, attributes: attributes))
      end

      def eval(id : String, attributes : AnyHash? = nil) : self
        append_node(Cogni::RegistryApi.build_node(self, "eval", id, attributes: attributes))
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
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        voice_config : AnyHash? = nil,
        guardrails_config : AnyHash? = nil,
        agent_id : String? = nil,
        agent : String? = nil,
        config : AnyHash? = nil,
        reason : String? = nil,
        node_kind_name : String? = nil,
        node_kind_attributes : AnyHash? = nil,
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
