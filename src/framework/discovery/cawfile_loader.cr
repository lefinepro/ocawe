require "rcl"
require "json"

module ACD
  module Discovery
    struct CawfileBundle
      getter id : String
      getter version : String?
      getter description : String?
      getter packages : Array(String)
      getter keys : Array(CawfileKeySpec)
      getter agents : Array(CawfileAgentSpec)
      getter skills : Array(CawfileSkillSpec)
      getter workflow_steps : Array(CawfileWorkflowStep)
      # Embedded config (mirrors ocawe.config.rcl fields)
      getter config_api : Array(String)
      getter config_federation : Hash(String, RCL::Value)
      getter config_datasets : Hash(String, RCL::Value)
      getter config_node_kinds : Hash(String, RCL::Value)
      getter config_functions : Hash(String, RCL::Value)
      getter config_mcp : Hash(String, RCL::Value)

      def initialize(
        @id : String,
        @version : String? = nil,
        @description : String? = nil,
        @packages : Array(String) = [] of String,
        @keys : Array(CawfileKeySpec) = [] of CawfileKeySpec,
        @agents : Array(CawfileAgentSpec) = [] of CawfileAgentSpec,
        @skills : Array(CawfileSkillSpec) = [] of CawfileSkillSpec,
        @workflow_steps : Array(CawfileWorkflowStep) = [] of CawfileWorkflowStep,
        @config_api : Array(String) = ["classic"] of String,
        @config_federation : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_datasets : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_node_kinds : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_functions : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_mcp : Hash(String, RCL::Value) = {} of String => RCL::Value
      )
      end
    end

    struct CawfileKeySpec
      getter name : String
      getter required : Bool
      getter description : String?
      getter provider : String?

      def initialize(@name : String, @required : Bool = false, @description : String? = nil, @provider : String? = nil)
      end
    end

    struct CawfileAgentSpec
      getter id : String
      getter prompt : String?
      getter model : String?
      getter description : String?
      getter voice_config : Hash(String, String)?
      getter guardrails_config : Hash(String, String)?

      def initialize(
        @id : String,
        @prompt : String? = nil,
        @model : String? = nil,
        @description : String? = nil,
        @voice_config : Hash(String, String)? = nil,
        @guardrails_config : Hash(String, String)? = nil
      )
      end
    end

    struct CawfileSkillSpec
      getter id : String
      getter name : String?
      getter description : String?
      getter file : String?

      def initialize(@id : String, @name : String? = nil, @description : String? = nil, @file : String? = nil)
      end
    end

    struct CawfileWorkflowStep
      getter type : String
      getter id : String
      getter params : Hash(String, JSON::Any)

      def initialize(@type : String, @id : String, @params : Hash(String, JSON::Any) = {} of String => JSON::Any)
      end
    end

    class CawfileLoader
      CAWFILE_NAMES = ["Cawfile", ".caw"]

      def self.find_cawfile(dir : String) : String?
        CAWFILE_NAMES.each do |name|
          path = File.join(dir, name)
          return path if File.file?(path)
        end
        nil
      end

      def self.load(dir : String, id : String) : CawfileBundle?
        path = find_cawfile(dir)
        return nil unless path

        doc = RCL.parse_file(path)
        workflow_block = find_workflow_block(doc)

        if workflow_block
          workflow_id = workflow_block.argument || id
          bundles = [parse_workflow_block_content(workflow_block, workflow_id)]
        else
          # No workflow block: treat root-level blocks as config + anonymous workflow
          bundles = [parse_root_document(doc, id)]
        end

        bundles.first
      end

      private def self.find_workflow_block(doc : RCL::Document) : RCL::BlockNode?
        doc.blocks.each do |top_block|
          # Top-level named block: workflow "name" do ... end
          # OR top-level block: workflow do ... end
          return top_block if top_block.name == "workflow"
        end
        nil
      end

      private def self.parse_workflow_block_content(block : RCL::BlockNode, workflow_id : String) : CawfileBundle
        packages = ast_rcl_string_array(block["packages"]?)
        version = ast_rcl_string(block["version"]?)
        description = ast_rcl_string(block["description"]?)

        keys = [] of CawfileKeySpec
        each_named_child(block, "key") do |arg, child|
          ast_bool = ast_rcl_bool(child["required"]?)
          keys << CawfileKeySpec.new(
            name: arg,
            required: ast_bool,
            description: ast_rcl_string(child["description"]?),
            provider: ast_rcl_string(child["provider"]?)
          )
        end

        agents = [] of CawfileAgentSpec
        each_named_child(block, "agent") do |arg, child|
          agents << CawfileAgentSpec.new(
            id: arg,
            prompt: ast_rcl_string(child["prompt"]?),
            model: ast_rcl_string(child["model"]?),
            description: ast_rcl_string(child["description"]?),
            voice_config: ast_rcl_string_h(child["voice"]?),
            guardrails_config: ast_rcl_string_h(child["guardrails"]?)
          )
        end

        skills = [] of CawfileSkillSpec
        each_named_child(block, "skill") do |arg, child|
          skills << CawfileSkillSpec.new(
            id: arg,
            name: ast_rcl_string(child["name"]?),
            description: ast_rcl_string(child["description"]?),
            file: ast_rcl_string(child["file"]?)
          )
        end

        workflow_steps = [] of CawfileWorkflowStep
        each_named_child(block, "step") do |arg, child|
          workflow_steps << parse_step(arg, child)
        end

        # Config sub-blocks
        api_val = ["classic"] of String
        fed = {} of String => RCL::Value
        ds = {} of String => RCL::Value
        nk = {} of String => RCL::Value
        fn = {} of String => RCL::Value
        mcp = {} of String => RCL::Value

        block.blocks.each do |name, child|
          case name
          when "api"
            api_val = block_to_string_array(child)
          when "federation"
            fed = block_to_rcl_value_h(child)
          when "datasets"
            ds = block_to_rcl_value_h(child)
          when "node_kinds"
            nk = block_to_rcl_value_h(child)
          when "functions"
            fn = block_to_rcl_value_h(child)
          when "mcp"
            mcp = block_to_rcl_value_h(child)
          end
        end

        CawfileBundle.new(
          id: workflow_id,
          version: version,
          description: description,
          packages: packages,
          keys: keys,
          agents: agents,
          skills: skills,
          workflow_steps: workflow_steps,
          config_api: api_val,
          config_federation: fed,
          config_datasets: ds,
          config_node_kinds: nk,
          config_functions: fn,
          config_mcp: mcp
        )
      end

      private def self.parse_root_document(doc : RCL::Document, id : String) : CawfileBundle
        # Treat top-level named blocks as workflow children when no workflow block
        steps = [] of CawfileWorkflowStep
        agents = [] of CawfileAgentSpec
        skills = [] of CawfileSkillSpec
        keys = [] of CawfileKeySpec

        doc.blocks.each do |block|
          case block.name
          when "agent"
            agents << parse_agent_block_node(block)
          when "skill"
            skills << parse_skill_block_node(block)
          when "key"
            keys << parse_key_block_node(block)
          else
            steps << parse_step_block_node(block)
          end
        end

        CawfileBundle.new(
          id: id,
          workflow_steps: steps,
          agents: agents,
          skills: skills,
          keys: keys
        )
      end

      private def self.parse_step(arg : String, block : RCL::BlockNode) : CawfileWorkflowStep
        parts = arg.split("-", 2)
        type = parts[0]
        id_arg = parts[1] || arg
        params = {} of String => JSON::Any
        block.properties.each do |k, v|
          params[k] = ast_node_to_json(v)
        end
        block.blocks.each do |k, v|
          params[k] = ast_node_to_json(v)
        end
        CawfileWorkflowStep.new(type: type, id: id_arg, params: params)
      end

      private def self.parse_agent_block_node(block : RCL::BlockNode) : CawfileAgentSpec
        CawfileAgentSpec.new(
          id: block.argument || "agent",
          prompt: ast_rcl_string(block["prompt"]?),
          model: ast_rcl_string(block["model"]?),
          description: ast_rcl_string(block["description"]?)
        )
      end

      private def self.parse_skill_block_node(block : RCL::BlockNode) : CawfileSkillSpec
        CawfileSkillSpec.new(
          id: block.argument || "skill",
          name: ast_rcl_string(block["name"]?),
          description: ast_rcl_string(block["description"]?),
          file: ast_rcl_string(block["file"]?)
        )
      end

      private def self.parse_key_block_node(block : RCL::BlockNode) : CawfileKeySpec
        CawfileKeySpec.new(
          name: block.argument || "key",
          required: ast_rcl_bool(block["required"]?),
          description: ast_rcl_string(block["description"]?),
          provider: ast_rcl_string(block["provider"]?)
        )
      end

      private def self.parse_step_block_node(block : RCL::BlockNode) : CawfileWorkflowStep
        type = block.name
        id = block.argument || type
        params = {} of String => JSON::Any
        block.properties.each do |k, v|
          params[k] = ast_node_to_json(v)
        end
        block.blocks.each do |k, v|
          params[k] = ast_node_to_json(v)
        end
        CawfileWorkflowStep.new(type: type, id: id, params: params)
      end

      private def self.each_named_child(parent : RCL::BlockNode, name : String, & : String, RCL::BlockNode ->)
        parent.named_blocks.each do |nb|
          if nb.name == name
            arg = nb.argument
            next unless arg
            yield arg, nb
          end
        end
        parent.blocks.each do |bname, bnode|
          next unless bname == name
          arg = bnode.argument
          next unless arg
          yield arg, bnode
        end
      end

      private def self.block_to_string_array(block : RCL::BlockNode) : Array(String)
        out = [] of String
        block.properties.each do |_k, v|
          if v.is_a?(RCL::StringNode)
            out << v.value
          end
        end
        out
      end

      private def self.block_to_rcl_value_h(block : RCL::BlockNode) : Hash(String, RCL::Value)
        hash_out = {} of String => RCL::Value
        block.properties.each do |k, v|
          hash_out[k] = ast_node_to_value(v)
        end
        block.blocks.each do |k, v|
          hash_out[k] = ast_node_to_value(v)
        end
        hash_out
      end

      private def self.ast_rcl_string(node : RCL::ASTNode?) : String?
        return nil unless node
        case node
        when RCL::StringNode
          node.value
        when RCL::NumberNode, RCL::BooleanNode
          node.value.to_s
        else
          nil
        end
      end

      private def self.ast_rcl_bool(node : RCL::ASTNode?, default : Bool = false) : Bool
        return default unless node
        case node
        when RCL::BooleanNode
          node.value
        when RCL::StringNode
          node.value.strip.downcase.in?("true", "1", "yes")
        else
          default
        end
      end

      private def self.ast_rcl_string_array(node : RCL::ASTNode?) : Array(String)
        return [] of String unless node
        arr = node.as?(RCL::ArrayNode)
        return [] of String unless arr
        arr.elements.compact_map { |e| e.is_a?(RCL::StringNode) ? e.value : nil }
      end

      private def self.ast_rcl_string_h(node : RCL::ASTNode?) : Hash(String, String)?
        return nil unless node
        block = node.as?(RCL::BlockNode)
        return nil unless block
        result = {} of String => String
        block.properties.each do |k, v|
          result[k] = v.is_a?(RCL::StringNode) ? v.value : v.to_s
        end
        result.empty? ? nil : result
      end

      private def self.ast_node_to_value(node : RCL::ASTNode) : RCL::Value
        case node
        when RCL::StringNode
          node.value
        when RCL::NumberNode
          node.value
        when RCL::BooleanNode
          node.value
        when RCL::ArrayNode
          node.elements.map { |e| ast_node_to_value(e) }
        when RCL::BlockNode
          h = {} of String => RCL::Value
          node.properties.each do |k, v|
            h[k] = ast_node_to_value(v)
          end
          node.blocks.each do |k, v|
            h[k] = ast_node_to_value(v)
          end
          h
        else
          ""
        end
      end

      private def self.ast_node_to_json(node : RCL::ASTNode) : JSON::Any
        case node
        when RCL::StringNode
          JSON.parse(node.value.to_json)
        when RCL::NumberNode
          JSON.parse(node.value.to_json)
        when RCL::BooleanNode
          JSON.parse(node.value.to_json)
        when RCL::ArrayNode
          JSON.parse(node.elements.map { |e| ast_node_to_json(e) }.to_json)
        when RCL::BlockNode
          h = {} of String => JSON::Any
          node.properties.each do |k, v|
            h[k] = ast_node_to_json(v)
          end
          node.blocks.each do |k, v|
            h[k] = ast_node_to_json(v)
          end
          node.named_blocks.each do |nb|
            arg = nb.argument
            key = arg ? "#{nb.name}-#{arg}" : nb.name
            h[key] = ast_node_to_json(nb)
          end
          JSON.parse(h.to_json)
        else
          JSON.parse("null")
        end
      end
    end
  end
end
