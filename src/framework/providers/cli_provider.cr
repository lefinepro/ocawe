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

      QUIET_PERIOD = 1.5

      @@mutex = Mutex.new
      @@processes = {} of String => NamedTuple(
        process: Process,
        stdin_writer: IO,
        stdout_reader: IO,
        started_at: Time,
      )

      def initialize(
        @ocawe_port : Int32 = ENV["OCAWE_PORT"]?.try(&.to_i) || 4111,
        @internal_key : String = ENV["OCAWE_INTERNAL_KEY"]? || "ocawe_internal"
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        binary = CLI_BINARIES[request.model]? || request.model
        text = send_prompt(binary, request.prompt)
        TextGenerationResponse.new(provider: "cli", model: request.model, text: text)
      end

      private def send_prompt(binary : String, prompt : String) : String
        entry = get_or_launch(binary)

        entry[:stdin_writer].puts(prompt)
        entry[:stdin_writer].flush

        buf = Bytes.new(4096)
        parts = [] of String
        loop do
          ready = IO.select([entry[:stdout_reader]], nil, nil, QUIET_PERIOD)
          break unless ready
          count = entry[:stdout_reader].read(buf)
          break if count == 0
          parts << String.new(buf[0, count])
        end
        parts.join
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
        stdout_reader, stdout_writer = IO.pipe

        ocawe_base = "http://localhost:#{@ocawe_port}"

        process = Process.new(
          binary,
          input: stdin_reader,
          output: stdout_writer,
          error: stdout_writer,
          env: {
            "ANTHROPIC_BASE_URL"   => ocawe_base,
            "ANTHROPIC_API_KEY"    => @internal_key,
            "ANTHROPIC_AUTH_TOKEN" => @internal_key,
            "OPENAI_BASE_URL"      => "#{ocawe_base}/v1",
            "OPENAI_API_KEY"       => @internal_key,
            "GEMINI_API_KEY"       => @internal_key,
            "GOOGLE_GEMINI_BASE_URL" => ocawe_base,
            "LLM_BASE_URL"         => "#{ocawe_base}/v1",
            "LLM_API_KEY"          => @internal_key,
            "OCAWE_PORT"           => @ocawe_port.to_s,
            "OCAWE_INTERNAL_KEY"   => @internal_key,
          }
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
