module ACD
  module Kemal
    class App
      private def parse_runtime_literal(literal : String, workflow_file : String) : JSON::Any
        stripped = literal.strip
        begin
          if stripped.starts_with?("{")
            return JSON.parse(parse_runtime_object(stripped, workflow_file).to_json)
          end
          if stripped.starts_with?("[")
            return JSON.parse(stripped)
          end
          JSON.parse(stripped)
        rescue
          if stripped.starts_with?("\"") && stripped.ends_with?("\"")
            return JSON.parse(stripped)
          end
          JSON.parse(stripped.to_json)
        end
      end

      private def compile_required_function_schema(
        literal : String?,
        workflow_file : String,
        fn_name : String,
        kind : String
      ) : Ocawe::Workflows::DSL::Validator
        raise "#{workflow_file}: function #{fn_name} requires #{kind}_schema" unless literal
        stripped = literal.strip
        Ocawe::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: function #{fn_name} #{kind} schema")
      end

      private def compile_optional_function_schema(
        literal : String?,
        workflow_file : String,
        fn_name : String,
        kind : String
      ) : Ocawe::Workflows::DSL::Validator?
        return nil unless literal
        stripped = literal.strip
        Ocawe::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: function #{fn_name} #{kind} schema")
      end

      private def ensure_output_schema_superset!(
        workflow_file : String,
        fn_name : String,
        input_schema : Ocawe::Workflows::DSL::Validator,
        output_schema : Ocawe::Workflows::DSL::Validator
      )
        Ocawe::Workflows::DSL::Compatibility.ensure_output_superset!(input_schema, output_schema)
      rescue ex : Ocawe::Workflows::DSL::ValidationError
        raise "#{workflow_file}: function #{fn_name} output_schema must cover input_schema: #{ex.message}"
      end

      private def split_top_level_params(value : String) : Array(String)
        parts = [] of String
        current = ""
        depth_paren = 0
        depth_brace = 0
        depth_bracket = 0
        in_string = false
        escaped = false

        value.each_char do |ch|
          if in_string
            current += ch.to_s
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == '"'
              in_string = false
            end
            next
          end

          case ch
          when '"'
            in_string = true
            current += ch.to_s
          when '('
            depth_paren += 1
            current += ch.to_s
          when ')'
            depth_paren -= 1 if depth_paren > 0
            current += ch.to_s
          when '{'
            depth_brace += 1
            current += ch.to_s
          when '}'
            depth_brace -= 1 if depth_brace > 0
            current += ch.to_s
          when '['
            depth_bracket += 1
            current += ch.to_s
          when ']'
            depth_bracket -= 1 if depth_bracket > 0
            current += ch.to_s
          when ','
            if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0
              token = current.strip
              parts << token unless token.empty?
              current = ""
            else
              current += ch.to_s
            end
          else
            current += ch.to_s
          end
        end

        token = current.strip
        parts << token unless token.empty?
        parts
      end

      private def collect_balanced_expression(
        initial : String,
        lines : Array(String),
        next_line : Int32,
        end_line : Int32,
        context : String,
        workflow_file : String
      ) : NamedTuple(value: String, next_index: Int32)
        expression = initial.strip
        index = next_line
        paren, brace, bracket = scan_structure_balance(expression)

        while (paren > 0 || brace > 0 || bracket > 0) && index < end_line
          continuation = lines[index].strip
          expression = "#{expression} #{continuation}"
          d_paren, d_brace, d_bracket = scan_structure_balance(continuation)
          paren += d_paren
          brace += d_brace
          bracket += d_bracket
          index += 1
        end

        if paren != 0 || brace != 0 || bracket != 0
          raise "#{workflow_file}: #{context} has unbalanced expression"
        end

        {value: expression, next_index: index}
      end

      private def scan_structure_balance(value : String) : Tuple(Int32, Int32, Int32)
        paren = 0
        brace = 0
        bracket = 0
        in_string = false
        escaped = false

        value.each_char do |ch|
          if in_string
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == '"'
              in_string = false
            end
            next
          end

          case ch
          when '"'
            in_string = true
          when '('
            paren += 1
          when ')'
            paren -= 1
          when '{'
            brace += 1
          when '}'
            brace -= 1
          when '['
            bracket += 1
          when ']'
            bracket -= 1
          end
        end

        {paren, brace, bracket}
      end

      private def parse_optional_string(literal : String?) : String?
        return nil unless literal
        return nil unless literal.starts_with?('"') && literal.ends_with?('"') && literal.size >= 2
        literal[1, literal.size - 2]
      end

      private def parse_runtime_object(literal : String, workflow_file : String) : Ocawe::Workflow::AnyHash
        parsed = YAML.parse(literal)
        hash = JSON.parse(parsed.to_json).as_h?
        raise "#{workflow_file}: runtime must be an object: #{literal}" unless hash
        hash
      rescue ex
        raise "#{workflow_file}: invalid runtime object '#{literal}': #{ex.message}"
      end

      private def parse_workspace_annotation_params(content : String, workflow_file : String) : Ocawe::Workflow::AnyHash
        parse_runtime_object("{#{content}}", workflow_file)
      end

    end
  end
end
