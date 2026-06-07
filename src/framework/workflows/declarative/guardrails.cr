module Ocawe
  module Workflow
    module Guardrails
      class Violation < Exception
      end

      def self.validate_input!(agent_id : String, text : String, config : AnyHash?) : Nil
        validate_stage!("input", agent_id, text, config.try(&.["input"]?).try(&.as_h?))
      end

      def self.validate_output!(agent_id : String, text : String, config : AnyHash?) : Nil
        validate_stage!("output", agent_id, text, config.try(&.["output"]?).try(&.as_h?))
      end

      private def self.validate_stage!(stage : String, agent_id : String, text : String, rules : AnyHash?) : Nil
        return unless rules

        if max_length = rules["max_length"]?.try(&.as_i?)
          if text.size > max_length
            raise Violation.new("guardrail violation: #{agent_id} #{stage}.max_length exceeded (#{text.size} > #{max_length})")
          end
        end

        if blocked_terms = rules["blocked_terms"]?.try(&.as_a?)
          lower_text = text.downcase
          blocked_terms.each do |term_any|
            term = term_any.as_s?
            next unless term
            if lower_text.includes?(term.downcase)
              raise Violation.new("guardrail violation: #{agent_id} #{stage}.blocked_terms matched '#{term}'")
            end
          end
        end

        if blocked_patterns = rules["blocked_patterns"]?.try(&.as_a?)
          blocked_patterns.each do |pattern_any|
            pattern = pattern_any.as_s?
            next unless pattern
            begin
              regex = Regex.new(pattern)
              if regex.matches?(text)
                raise Violation.new("guardrail violation: #{agent_id} #{stage}.blocked_patterns matched '#{pattern}'")
              end
            rescue ex : Regex::Error
              raise Violation.new("guardrail violation: #{agent_id} #{stage}.blocked_patterns invalid regex '#{pattern}': #{ex.message}")
            end
          end
        end
      end
    end
  end
end
