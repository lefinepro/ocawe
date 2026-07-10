require "../frontmatter"
require "json"

module ACD
  module Agents
    struct LoadedAgent
      getter id : String
      getter file_path : String
      getter description : String
      getter frontmatter : Hash(String, YAML::Any)
      getter prompt : String
      getter model : String?
      getter voice_config : Hash(String, JSON::Any)?
      getter guardrails_config : Hash(String, JSON::Any)?
      getter input_schema_dsl : String?
      getter output_schema_dsl : String?
      getter resume_schema_dsl : String?

      def initialize(
        @id : String,
        @file_path : String,
        @description : String,
        @frontmatter : Hash(String, YAML::Any),
        @prompt : String,
        @model : String? = nil,
        @voice_config : Hash(String, JSON::Any)? = nil,
        @guardrails_config : Hash(String, JSON::Any)? = nil,
        @input_schema_dsl : String? = nil,
        @output_schema_dsl : String? = nil,
        @resume_schema_dsl : String? = nil,
      )
      end
    end

    class Loader
      def load_dir(path : String) : Array(LoadedAgent)
        return [] of LoadedAgent unless Dir.exists?(path)

        agents = [] of LoadedAgent
        agent_files(path).each do |file|
          content = File.read(file)
          parsed = begin
            Frontmatter.parse_markdown(content, file)
          rescue ex : Frontmatter::ParseError
            next if File.extname(file) == ".org" && ex.message.to_s.includes?("missing YAML frontmatter")
            raise ex
          end

          description = parsed.data["description"]?.try(&.as_s?)
          raise "#{file}: agent frontmatter requires 'description'" unless description

          schema_blocks = extract_schema_blocks(parsed.body)
          model = parsed.data["model"]?.try(&.as_s?)
          voice_config = parse_hash_frontmatter(parsed.data["voice"]?, file, "voice")
          guardrails_config = parse_hash_frontmatter(parsed.data["guardrails"]?, file, "guardrails")
          validate_guardrails_config(file, guardrails_config)

          agents << LoadedAgent.new(
            id: File.basename(file, File.extname(file)),
            file_path: file,
            description: description,
            frontmatter: parsed.data,
            prompt: schema_blocks[:prompt],
            model: model,
            voice_config: voice_config,
            guardrails_config: guardrails_config,
            input_schema_dsl: schema_blocks[:input_schema_dsl],
            output_schema_dsl: schema_blocks[:output_schema_dsl],
            resume_schema_dsl: schema_blocks[:resume_schema_dsl],
          )
        end
        agents
      end

      private def agent_files(path : String) : Array(String)
        (Dir.glob(File.join(path, "*.md")) + Dir.glob(File.join(path, "*.org"))).sort
      end

      private def parse_hash_frontmatter(value : YAML::Any?, file : String, key : String) : Hash(String, JSON::Any)?
        return nil unless value

        hash = value.as_h?
        raise "#{file}: agent frontmatter '#{key}' must be an object" unless hash

        normalized = {} of String => JSON::Any
        hash.each do |k, v|
          normalized[k.to_s] = JSON.parse(v.to_json)
        end
        normalized
      end

      private def validate_guardrails_config(file : String, guardrails : Hash(String, JSON::Any)?) : Nil
        return unless guardrails
        %w(input output).each do |key|
          next unless any = guardrails[key]?
          raise "#{file}: guardrails.#{key} must be an object" unless any.as_h?
        end
      end

      private def extract_schema_blocks(body : String) : NamedTuple(prompt: String, input_schema_dsl: String?, output_schema_dsl: String?, resume_schema_dsl: String?)
        prompt_lines = [] of String
        input_schema_dsl = nil.as(String?)
        output_schema_dsl = nil.as(String?)
        resume_schema_dsl = nil.as(String?)

        in_schema_block = false
        schema_kind = nil.as(String?)
        schema_end = nil.as(String?)
        schema_opener = nil.as(String?)
        buffer = [] of String

        body.each_line do |line|
          if !in_schema_block
            if match = line.match(/^\s*```crystal\s+schema:(input|output|resume)\s*$/)
              in_schema_block = true
              schema_kind = match[1]
              schema_end = "```"
              schema_opener = line
              buffer.clear
              next
            end

            if match = line.match(/^\s*#\+begin_src\s+crystal\s+schema:(input|output|resume)\s*$/)
              in_schema_block = true
              schema_kind = match[1]
              schema_end = "#+end_src"
              schema_opener = line
              buffer.clear
              next
            end

            prompt_lines << line
            next
          end

          if line.strip == schema_end
            snippet = buffer.join.strip
            unless snippet.empty?
              if schema_kind == "input" && input_schema_dsl.nil?
                input_schema_dsl = snippet
              elsif schema_kind == "output" && output_schema_dsl.nil?
                output_schema_dsl = snippet
              elsif schema_kind == "resume" && resume_schema_dsl.nil?
                resume_schema_dsl = snippet
              end
            end

            in_schema_block = false
            schema_kind = nil
            schema_end = nil
            schema_opener = nil
            buffer.clear
            next
          end

          buffer << line
        end

        if in_schema_block
          prompt_lines << "#{schema_opener}\n"
          prompt_lines.concat(buffer)
        end

        {
          prompt:            prompt_lines.join.strip,
          input_schema_dsl:  input_schema_dsl,
          output_schema_dsl: output_schema_dsl,
          resume_schema_dsl: resume_schema_dsl,
        }
      end
    end
  end
end
