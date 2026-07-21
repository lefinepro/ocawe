require "http/client"
require "json"
require "uuid"

require "../discovery/cawfile_loader"

module Ocawe
  module Testing
    struct TestResult
      getter name : String
      getter workflow_id : String
      getter passed : Bool
      getter expected : String
      getter actual : String
      getter error : String?
      getter missing_tags : Array(String)
      getter tag : String?

      def initialize(
        @name : String,
        @workflow_id : String,
        @passed : Bool,
        @expected : String,
        @actual : String = "",
        @error : String? = nil,
        @missing_tags : Array(String) = [] of String,
        @tag : String? = nil,
      )
      end
    end

    class CawfileRunner
      alias Transport = Proc(String, String, String)
      alias TagGenerator = Proc(String, String)
      DEFAULT_BASE_URL = "http://127.0.0.1:4111"

      getter base_url : String

      def initialize(
        @base_url : String,
        @transport : Transport? = nil,
        @tag_generator : TagGenerator? = nil,
      )
      end

      def self.default_base_url : String
        DEFAULT_BASE_URL
      end

      def run(bundle : ACD::Discovery::CawfileBundle) : Array(TestResult)
        results = [] of TestResult
        bundle.tests.each do |test|
          test.assertions.each do |assertion|
            results << run_assertion(test.name, assertion)
          end
        end
        results
      end

      def run_assertion(test_name : String, assertion : ACD::Discovery::CawfileTestAssertion) : TestResult
        tag = generated_tag(test_name)
        tagged_input = input_with_tag(assertion.input, tag)
        response = if assertion.workflow_id.starts_with?("workflow/")
                     post_chat_completion(assertion.workflow_id, tagged_input)
                   else
                     post_workflow_run(assertion.workflow_id, tagged_input)
                   end
        response = wait_for_result(assertion.workflow_id, response, assertion.wait_seconds) if assertion.wait_seconds > 0
        actual = extract_actual(response)
        expected = assertion.equality
        comparison_actual = strip_test_tag(actual, tag)
        missing_tags = actual.includes?(tag) ? [] of String : [tag]
        TestResult.new(
          test_name,
          assertion.workflow_id,
          comparison_actual == expected.strip && missing_tags.empty?,
          expected,
          actual,
          missing_tags: missing_tags,
          tag: tag
        )
      rescue ex
        TestResult.new(test_name, assertion.workflow_id, false, assertion.equality, error: ex.message)
      end

      private def post_workflow_run(workflow_id : String, input : String) : String
        path = "/v1/workflows/#{URI.encode_path_segment(workflow_id)}/runs"
        body = {"input_data" => input_payload(input)}.to_json
        if transport = @transport
          return transport.call(path, body)
        end

        response = HTTP::Client.post(
          "#{@base_url.rstrip('/')}#{path}",
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: body
        )
        unless response.status.success?
          raise "workflow #{workflow_id} returned HTTP #{response.status_code}: #{response.body}"
        end
        response.body
      end

      private def post_chat_completion(model : String, input : String) : String
        path = "/v1/chat/completions"
        body = {
          "model"    => model,
          "messages" => [
            {
              "role"    => "user",
              "content" => input,
            },
          ],
        }.to_json
        if transport = @transport
          return transport.call(path, body)
        end

        response = HTTP::Client.post(
          "#{@base_url.rstrip('/')}#{path}",
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: body
        )
        unless response.status.success?
          raise "chat completion #{model} returned HTTP #{response.status_code}: #{response.body}"
        end
        response.body
      end

      private def input_payload(input : String) : JSON::Any
        stripped = input.strip
        return JSON.parse("{}") if stripped.empty?

        begin
          JSON.parse(stripped)
        rescue
          JSON.parse({"input" => input}.to_json)
        end
      end

      private def extract_actual(response_body : String) : String
        parsed = JSON.parse(response_body)
        pick_string(parsed, ["output", "text"]) ||
          pick_string(parsed, ["choices", "0", "message", "content"]) ||
          pick_string(parsed, ["output", "content"]) ||
          pick_string(parsed, ["output", "result"]) ||
          pick_string(parsed, ["state", "text"]) ||
          pick_string(parsed, ["state", "content"]) ||
          pick_string(parsed, ["state", "result"]) ||
          parsed.to_json
      end

      private def wait_for_result(workflow_id : String, response_body : String, wait_seconds : Int32) : String
        current = response_body
        return current if final_response?(current)

        deadline = Time.monotonic + wait_seconds.seconds
        while Time.monotonic < deadline
          sleep 250.milliseconds
          path = status_path(workflow_id, current)
          return current unless path
          current = get_status(path)
          return current if final_response?(current)
        end
        current
      end

      private def final_response?(response_body : String) : Bool
        parsed = JSON.parse(response_body)
        return true if extract_actual(response_body) != parsed.to_json
        status = parsed["status"]?.try(&.as_s?)
        !status || !{"queued", "pending", "running", "in_progress"}.includes?(status.downcase)
      rescue
        true
      end

      private def status_path(workflow_id : String, response_body : String) : String?
        parsed = JSON.parse(response_body)
        if status_url = parsed["status_url"]?.try(&.as_s?)
          return status_url
        end
        run_id = parsed["run_id"]?.try(&.as_s?)
        return nil unless run_id
        "/v1/workflows/#{URI.encode_path_segment(workflow_id)}/runs/#{URI.encode_path_segment(run_id)}"
      rescue
        nil
      end

      private def get_status(path : String) : String
        if transport = @transport
          return transport.call(path, "")
        end

        response = HTTP::Client.get("#{@base_url.rstrip('/')}#{path}")
        unless response.status.success?
          raise "status #{path} returned HTTP #{response.status_code}: #{response.body}"
        end
        response.body
      end

      private def pick_string(value : JSON::Any, path : Array(String)) : String?
        current = value
        path.each do |key|
          next_value = if array_index?(key)
                         array = current.as_a?
                         return nil unless array
                         array[key.to_i]?
                       else
                         object = current.as_h?
                         return nil unless object
                         object[key]?
                       end
          return nil unless next_value
          current = next_value
        end
        current.as_s?
      end

      private def array_index?(value : String) : Bool
        value.matches?(/^\d+$/)
      end

      private def generated_tag(test_name : String) : String
        if generator = @tag_generator
          return generator.call(test_name)
        end
        "#[#{slug(test_name)}-#{UUID.random}]"
      end

      private def input_with_tag(input : String, tag : String) : String
        stripped = input.strip
        stripped.empty? ? tag : "#{stripped} #{tag}"
      end

      private def strip_test_tag(value : String, tag : String) : String
        value.gsub(tag, "").strip
      end

      private def slug(value : String) : String
        slugged = value
          .downcase
          .gsub(/[^a-z0-9]+/, "-")
          .gsub(/^-+|-+$/, "")
        slugged.empty? ? "test" : slugged
      end
    end
  end
end
