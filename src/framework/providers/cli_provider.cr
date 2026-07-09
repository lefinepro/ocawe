require "./provider"

module OcaweCore
  module AI
    class CliProvider
      include Provider

      CLI_BINARIES = {
        "opencode"    => "opencode",
        "claude-code" => "claude-code",
        "codex"       => "codex",
        "antigravity" => "antigravity",
        "cline"       => "cline",
        "openhands"   => "openhands",
        "hermes"      => "hermes",
      }

      # CLIs that support --prompt "..." in non-interactive mode.
      PROMPT_CLIS = {"opencode", "claude-code", "codex"}

      CLI_TIMEOUT = 60.0

      @@mutex = Mutex.new
      @@processes = {} of String => NamedTuple(
        process: Process,
        stdin_writer: IO,
        stdout_reader: IO::FileDescriptor,
        started_at: Time,
      )

      def initialize(
        @ocawe_port : Int32 = ENV["OCAWE_PORT"]?.try(&.to_i) || 4111,
        @internal_key : String = ENV["OCAWE_INTERNAL_KEY"]? || "ocawe_internal"
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1" && request.api_key.nil?
          text = "[mock cli] #{request.prompt}"
          return TextGenerationResponse.new(provider: "cli", model: request.model, text: text)
        end

        binary = CLI_BINARIES[request.model]? || request.model

        unless Process.find_executable(binary)
          raise "CLI '#{binary}' not found in PATH. Install it in the container image."
        end

        if PROMPT_CLIS.includes?(binary)
          text = run_with_prompt(binary, request.prompt)
        else
          text = send_prompt(binary, request.prompt)
        end

        TextGenerationResponse.new(provider: "cli", model: request.model, text: text)
      end

      private def run_with_prompt(binary : String, prompt : String) : String
        write_cli_config(binary)

        stdout = IO::Memory.new
        combined = IO::Memory.new

        process = Process.new(
          binary,
          args: ["run", prompt, "--format", "json"],
          output: stdout,
          error: combined,
          env: cli_env,
          chdir: "/tmp",
        )
        status = process.wait

        out = stdout.to_s
        err = combined.to_s

        unless status.success?
          if out.empty?
            raise "CLI '#{binary}' exited with code #{status.exit_status}: #{err}"
          end
        end

        out.empty? ? err : out
      end

      private def send_prompt(binary : String, prompt : String) : String
        entry = get_or_launch(binary)

        entry[:stdin_writer].puts(prompt)
        entry[:stdin_writer].flush

        reader = entry[:stdout_reader]
        reader.read_timeout = CLI_TIMEOUT.seconds

        buf = Bytes.new(4096)
        parts = [] of String
        loop do
          begin
            count = reader.read(buf)
          rescue IO::TimeoutError
            break
          end
          break if count == 0
          parts << String.new(buf[0, count])
        end
        parts.join
      end

      private def cli_env : Hash(String, String)
        cfg = ACD::Kemal::App.provider_config
        provider = cfg[:provider]
        api_key = cfg[:api_key]
        base_url = cfg[:base_url].empty? ? "http://localhost:#{@ocawe_port}" : cfg[:base_url]
        model = cfg[:model]

        env_vars = {
          "OCAWE_PORT"         => @ocawe_port.to_s,
          "OCAWE_INTERNAL_KEY" => @internal_key,
        }

        unless model.empty?
          env_vars["ANTHROPIC_MODEL"] = model
          env_vars["OPENAI_MODEL"] = model
          env_vars["GEMINI_MODEL"] = model
          env_vars["GROQ_MODEL"] = model
          env_vars["MODEL"] = model
        end

        case provider
        when "anthropic"
          env_vars["ANTHROPIC_API_KEY"] = api_key
          env_vars["ANTHROPIC_BASE_URL"] = base_url
          env_vars["ANTHROPIC_AUTH_TOKEN"] = api_key
        when "openai"
          env_vars["OPENAI_API_KEY"] = api_key
          env_vars["OPENAI_BASE_URL"] = base_url
        when "google", "gemini"
          env_vars["GEMINI_API_KEY"] = api_key
          env_vars["GOOGLE_GENERATIVE_AI_API_KEY"] = api_key
          env_vars["GOOGLE_GEMINI_BASE_URL"] = base_url
        when "groq"
          env_vars["GROQ_API_KEY"] = api_key
          env_vars["GROQ_BASE_URL"] = base_url
        else
          env_vars["ANTHROPIC_API_KEY"] = api_key
          env_vars["ANTHROPIC_BASE_URL"] = base_url
          env_vars["OPENAI_API_KEY"] = api_key
          env_vars["OPENAI_BASE_URL"] = base_url
          env_vars["GEMINI_API_KEY"] = api_key
          env_vars["GOOGLE_GENERATIVE_AI_API_KEY"] = api_key
        end

        env_vars
      end

      private def write_cli_config(binary : String)
        case binary
        when "opencode"
          cfg = ACD::Kemal::App.provider_config
          provider_name = cfg[:provider]
          api_key = cfg[:api_key]
          base_url = cfg[:base_url].empty? ? "http://localhost:#{@ocawe_port}" : cfg[:base_url]
          model = cfg[:model].empty? ? nil : cfg[:model]

          home = ENV["HOME"]? || "/root"

          json = JSON.build do |j|
            j.object do
              j.field "providers" do
                j.object do
                  j.field provider_name do
                    j.object do
                      j.field "apiKey", api_key
                      j.field "baseURL", base_url
                      j.field "disabled", false
                    end
                  end
                end
              end
              j.field "agents" do
                j.object do
                  j.field "coder" do
                    j.object do
                      if model
                        j.field "model", model
                      else
                        j.field "model", "cli/opencode"
                      end
                    end
                  end
                end
              end
            end
          end

          File.write("#{home}/.opencode.json", json)
        end
      end

      private def get_or_launch(binary : String)
        @@mutex.synchronize do
          if entry = @@processes[binary]?
            unless entry[:process].terminated?
              return entry
            end
            @@processes.delete(binary)
          end
        end

        stdin_reader, stdin_writer = IO.pipe
        _stdout_read, _stdout_write = IO.pipe
        stdout_reader = _stdout_read.as(IO::FileDescriptor)
        stdout_writer = _stdout_write

        process = Process.new(
          binary,
          input: stdin_reader,
          output: stdout_writer,
          error: stdout_writer,
          env: cli_env,
        )
        stdin_reader.close

        entry = {
          process:        process,
          stdin_writer:   stdin_writer,
          stdout_reader:  stdout_reader,
          started_at:     Time.utc,
        }

        @@mutex.synchronize do
          @@processes[binary] = entry
        end

        entry
      end
    end
  end
end
