module Cogni
  module Workflow
    class WorkflowDefinition
      def agent(
        id : String,
        prompt : String? = nil,
        model : String? = nil,
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        voice_config : AnyHash? = nil,
        guardrails_config : AnyHash? = nil,
        workspace : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "agent",
          id,
          prompt: prompt,
          model: model,
          resume_schema: resume_schema,
          voice_config: voice_config,
          guardrails_config: guardrails_config,
          workspace: workspace,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def step(
        kind : Cogni::NodeKind,
        id : String? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        node_id = id || "#{kind.node}-#{@nodes.size}"
        append_node(Cogni::RegistryApi.build_node(
          self,
          "node_kind",
          node_id,
          node_kind_name: kind.node,
          node_kind_attributes: kind.attributes,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end


      def skill(
        id : String,
        agent_id : String? = nil,
        agent : String? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "skill",
          id,
          agent_id: agent_id,
          agent: agent,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      # Voice node implemented as first-class DSL behavior.
      # This keeps voice orchestration inside workflow DSL instead of auto-started tools.
      def voice(
        id : String,
        config : AnyHash = {} of String => JSON::Any,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "voice",
          id,
          config: config,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      # RAG node implemented as first-class DSL behavior.
      # This keeps retrieval/memory orchestration inside workflow DSL.
      def rag(
        id : String,
        config : AnyHash = {} of String => JSON::Any,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "rag",
          id,
          config: config,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def suspend(
        id : String,
        reason : String = "human input required",
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(Cogni::RegistryApi.build_node(
          self,
          "suspend",
          id,
          reason: reason,
          resume_schema: resume_schema,
          input_schema: input_schema,
          output_schema: output_schema,
        ))
      end

      def parallel(parallel_nodes : Array(WorkflowNode)) : self
        ensure_not_committed!

        aggregator = WorkflowNode.new("parallel-#{@nodes.size}", NodeKind::Control) do |ctx|
          branch_results = Array(Tuple(Int32, WorkflowNodeResult)).new
          ch = Channel(Tuple(Int32, WorkflowNodeResult)).new

          parallel_nodes.each_with_index do |node, idx|
            spawn do
              begin
                ch.send({idx, node.execute(with_context_for(ctx, node))})
              rescue ex
                ch.send({idx, WorkflowNodeResult.fail(ex.message || "parallel node failed")})
              end
            end
          end

          parallel_nodes.size.times { branch_results << ch.receive }
          branch_results.sort_by! { |(idx, _)| idx }

          merged = {} of String => JSON::Any
          suspend_labels = [] of String
          suspend_payloads = [] of JSON::Any
          failed_result = nil.as(WorkflowNodeResult?)

          branch_results.each do |(_, result)|
            case result.action
            when NodeAction::Continue.to_s.downcase
              if data = result.data
                data.each { |k, v| merged[k] = v }
              end
            when NodeAction::Suspend.to_s.downcase
              labels = result.resume_labels || [] of String
              labels.each { |label| suspend_labels << label unless suspend_labels.includes?(label) }
              suspend_payloads << JSON.parse((result.suspend_payload || {} of String => JSON::Any).to_json)
            else
              failed_result = result
              break
            end
          end

          if failed = failed_result
            next failed
          end

          if suspend_labels.empty?
            WorkflowNodeResult.continue(merged)
          else
            WorkflowNodeResult.suspend(
              {
                "type" => JSON.parse("parallel_suspend".to_json),
                "resume_labels" => JSON.parse(suspend_labels.to_json),
                "branches" => JSON.parse(suspend_payloads.to_json),
              },
              resume_labels: suspend_labels,
            )
          end
        end

        @nodes << aggregator
        self
      end

      def foreach(node : WorkflowNode) : self
        append_node(node)
      end

      def while_do(condition : String, nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "while-body")
        append_node(WorkflowNode.new("while-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while evaluate_condition(condition, with_state(ctx, merged)) && iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end

      def until_do(condition : String, nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "until-body")
        append_node(WorkflowNode.new("until-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while !evaluate_condition(condition, with_state(ctx, merged)) && iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end

      def loop_do(nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "loop-body")
        append_node(WorkflowNode.new("loop-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end
    end
  end
end
