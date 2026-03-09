module CogniCore
  module CLI
    class Main
      private def run_trigger_command(kind : String, target_id : String, args : Array(String)) : Nil
        endpoint = trigger_endpoint_for(kind)
        base_url = ENV["COGNI_TRIGGER_BASE_URL"]? || DEFAULT_TRIGGER_BASE_URL
        run_id = nil.as(String?)
        resource_id = nil.as(String?)
        input_json = nil.as(Hash(String, JSON::Any)?)
        prompt = nil.as(String?)
        system = nil.as(String?)
        metadata_json = nil.as(Hash(String, JSON::Any)?)

        OptionParser.parse(args) do |parser|
          parser.on("--base-url URL", "Trigger API base URL") { |v| base_url = v }
          parser.on("--run-id ID", "Optional run id") { |v| run_id = v }
          parser.on("--resource-id ID", "Optional resource id") { |v| resource_id = v }
          parser.on("--input-json JSON", "Full request payload JSON object") { |v| input_json = parse_input_json(v) }
          parser.on("--prompt TEXT", "Agent prompt shortcut (maps to payload.input)") { |v| prompt = v }
          parser.on("--system TEXT", "Agent system message") { |v| system = v }
          parser.on("--metadata-json JSON", "Agent metadata JSON object") { |v| metadata_json = parse_input_json(v) }
          parser.on("-h", "--help", "Show trigger help") do
            print_trigger_help(kind)
            exit(0)
          end
        end

        payload = input_json ? input_json.not_nil!.dup : ({} of String => JSON::Any)
        named_args, positional_args = parse_cli_tokens(args)

        case endpoint
        when "workflows"
          input_data = payload["input"]?.try(&.as_h?) || ({} of String => JSON::Any)
          merge_cli_tokens!(input_data, named_args, positional_args)
          payload["input"] = JSON.parse(input_data.to_json) unless input_data.empty? && !payload.has_key?("input")
          payload["run_id"] = json_any(run_id) if run_id
          payload["resource_id"] = json_any(resource_id) if resource_id
        when "functions"
          input_data = payload["input"]?.try(&.as_h?) || ({} of String => JSON::Any)
          merge_cli_tokens!(input_data, named_args, positional_args)
          payload["input"] = JSON.parse(input_data.to_json) unless input_data.empty? && !payload.has_key?("input")
          payload["run_id"] = json_any(run_id) if run_id
        when "agents"
          merge_cli_tokens!(payload, named_args, positional_args)
          if prompt && !payload.has_key?("input") && !payload.has_key?("prompt") && !payload.has_key?("messages")
            payload["input"] = json_any(prompt)
          end
          payload["system"] = json_any(system) if system
          payload["metadata"] = JSON.parse(metadata_json.not_nil!.to_json) if metadata_json
        when "skills"
          merge_cli_tokens!(payload, named_args, positional_args)
        else
          raise "unsupported trigger endpoint: #{endpoint}"
        end

        url = "#{trimmed_base_url(base_url)}/v1/triggers/#{endpoint}/#{target_id}"

        begin
          response = @trigger_invoker.call(url, payload.to_json)
          if success_status?(response.status_code)
            print_json_or_raw(response.body)
          else
            STDERR.puts "[cogni] #{kind} trigger failed: HTTP #{response.status_code}"
            print_json_or_raw(response.body, io: STDERR)
            exit(1)
          end
        rescue ex
          STDERR.puts "[cogni] failed to call #{kind} trigger: #{ex.message}"
          exit(1)
        end
      end
    end
  end
end
