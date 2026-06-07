module Ocawe
  module AgentFunctionHandlers
    extend self

    private def run_agent_cli(
      command : String,
      args : Array(String),
      prompt : String,
      env : Hash(String, String) = {} of String => String
    ) : Tuple(Process::Status, String, String, Array(String))
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      input = IO::Memory.new(prompt)
      resolved_args = args.map { |arg| arg == "{prompt}" ? prompt : arg }

      status = if resolved_args.includes?(prompt)
                 Process.run(command, args: resolved_args, output: stdout, error: stderr, env: env)
               elsif resolved_args.empty?
                 Process.run(command, input: input, output: stdout, error: stderr, env: env)
               else
                 Process.run(command, args: resolved_args, input: input, output: stdout, error: stderr, env: env)
               end

      {status, stdout.to_s, stderr.to_s, resolved_args}
    end

    private def extract_input_text(input : JSON::Any?) : String
      return "" unless input
      if text = input.as_s?
        return text
      end
      if hash = input.as_h?
        return hash["content"]?.try(&.as_s?) ||
          hash["text"]?.try(&.as_s?) ||
          hash["task"]?.try(&.as_s?) ||
          hash["prompt"]?.try(&.as_s?) ||
          input.to_json
      end
      input.to_json
    end

    private def has_model_flag?(args : Array(String)) : Bool
      args.any? { |arg| arg == "--model" || arg == "-m" || arg.starts_with?("--model=") }
    end

    private def resolve_string_param(
      ctx : Ocawe::Workflow::NodeContext,
      key : String,
      env_keys : Array(String) = [] of String,
      default : String? = nil
    ) : String?
      if value = workflow_param_from_ctx(ctx, key)
        if string = value.as_s?
          return string
        end
      end

      if value = input_param_from_ctx(ctx, key)
        if string = value.as_s?
          return string
        end
      end

      env_keys.each do |env_key|
        env_val = ENV[env_key]?
        return env_val if env_val && !env_val.empty?
      end

      default
    end

    private def resolve_string_array_param(
      ctx : Ocawe::Workflow::NodeContext,
      key : String,
      env_keys : Array(String) = [] of String
    ) : Array(String)
      env_keys.each do |env_key|
        env_val = ENV[env_key]?
        next unless env_val && !env_val.empty?
        return env_val.split(/[,\s]+/).map(&.strip).reject(&.empty?)
      end

      if value = workflow_param_from_ctx(ctx, key)
        return json_to_string_array(value)
      end

      if value = input_param_from_ctx(ctx, key)
        return json_to_string_array(value)
      end

      [] of String
    end

    private def workflow_param_from_ctx(ctx : Ocawe::Workflow::NodeContext, key : String) : JSON::Any?
      ctx.input_data[key]?
    end

    private def input_param_from_ctx(ctx : Ocawe::Workflow::NodeContext, key : String) : JSON::Any?
      input_payload = ctx.input_data["input"]?.try(&.as_h?)
      return nil unless input_payload
      input_payload[key]?
    end

    private def json_to_string_array(value : JSON::Any) : Array(String)
      if entries = value.as_a?
        return entries.compact_map(&.as_s?)
      end
      if single = value.as_s?
        return [single]
      end
      [] of String
    end
  end
end
