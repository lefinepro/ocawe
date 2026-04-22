module ACD
  module Kemal
    class App
      private def parse_dataset_block(ctx : WorkflowParserContext, dataset_id : String, start_line : Int32, end_line : Int32) : Nil
        description = nil.as(String?)
        schema_description = nil.as(String?)
        schema_source = nil.as(String?)
        source_path = nil.as(String?)
        source_format = nil.as(String?)
        source_options = nil.as(Cogni::Dataset::AnyHash?)
        seed_items = [] of Cogni::Dataset::AnyHash

        i = start_line
        while i < end_line
          line = ctx.lines[i].strip
          i += 1
          next if line.empty? || line.starts_with?("#")

          if match = line.match(/^\s*description\s+"([^"]+)"\s*$/)
            description = match[1]
            next
          end

          if match = line.match(/^\s*schema_description\s+"([^"]+)"\s*$/)
            schema_description = match[1]
            next
          end

          if line.match(/^\s*schema\s+/)
            initial = line.sub(/^\s*schema\s+/, "")
            collected = collect_balanced_expression(initial, ctx.lines, i, end_line, "dataset #{dataset_id} schema", ctx.workflow_file)
            schema_source = collected[:value]
            i = collected[:next_index]
            next
          end

          if match = line.match(/^\s*(file|json|csv)\s+"([^"]+)"(.*)$/)
            source_path = match[2]
            attributes = parse_line_attributes(match[3]? || "", ctx.workflow_file, "dataset #{dataset_id} #{match[1]}")
            if match[1] == "file"
              source_format = parse_optional_string(attributes["format"]?) || source_format
              source_options = extract_attributes(attributes, Set{"format"}, ctx.workflow_file)
            else
              source_format = match[1]
              source_options = extract_attributes(attributes, Set(String).new, ctx.workflow_file)
            end
            next
          end

          if line.match(/^\s*item\s*\(/)
            collected = collect_balanced_expression(line, ctx.lines, i, end_line, "dataset #{dataset_id} item", ctx.workflow_file)
            expression = collected[:value]
            i = collected[:next_index]
            match = expression.match(/^\s*item\s*\((.*)\)\s*$/)
            raise "#{ctx.workflow_file}: invalid dataset item syntax '#{expression}'" unless match
            parsed = parse_runtime_literal(match[1], ctx.workflow_file)
            hash = parsed.as_h?
            raise "#{ctx.workflow_file}: dataset item must be an object" unless hash
            seed_items << hash
            next
          end

          if line.match(/^\s*items\s*\(/)
            collected = collect_balanced_expression(line, ctx.lines, i, end_line, "dataset #{dataset_id} items", ctx.workflow_file)
            expression = collected[:value]
            i = collected[:next_index]
            match = expression.match(/^\s*items\s*\((.*)\)\s*$/)
            raise "#{ctx.workflow_file}: invalid dataset items syntax '#{expression}'" unless match
            parsed = parse_runtime_literal(match[1], ctx.workflow_file)
            array = parsed.as_a?
            raise "#{ctx.workflow_file}: dataset items must be an array of objects" unless array
            array.each do |entry|
              hash = entry.as_h?
              raise "#{ctx.workflow_file}: dataset items must be an array of objects" unless hash
              seed_items << hash
            end
            next
          end

          raise "#{ctx.workflow_file}: unsupported dataset directive '#{line}'"
        end

        ctx.dataset_service.register_from_dsl(
          dataset_id,
          source_file: ctx.workflow_file,
          description: description,
          schema_description: schema_description,
          schema_source: schema_source,
          seed_items: seed_items,
          source_path: source_path,
          source_format: source_format,
          source_options: source_options,
          base_dir: ctx.workflow_root,
        )
      end
    end
  end
end
