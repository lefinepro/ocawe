require "./e2e_spec_helper"
require "http/client"
require "socket"
require "uri"

# Process-level harness for the cross-process ActivityPub E2E spec.
#
# Every peer created here is a real, separate `ocawecore` OS process with its
# own temporary workflow bundle, loopback port, actor URL, RSA private key and
# log files (R-002). Nothing in this module reaches into Ocawe internals: the
# harness only speaks the public HTTP surface (`/health`, the classic run API
# and the ActivityPub actor/inbox/outbox routes) and signs requests with the
# production `Aptok::Signatures` primitive.
module FederationE2E
  extend self

  # The spec runs against a prebuilt runtime binary. `src/ocawe.cr` only calls
  # `OcaweCore.run` when it is compiled with `-Docawe_runtime_main`, so a binary
  # built without that flag starts and exits immediately.
  RUNTIME_BINARY_ENV     = "OCAWE_E2E_RUNTIME_BIN"
  DEFAULT_RUNTIME_BINARY = "bin/ocawecore"
  RUNTIME_BUILD_COMMAND  = "nix build .#ocawe && cp -L result/bin/ocawecore bin/ocawecore"

  ACTIVITY_CONTENT_TYPE = "application/activity+json"

  # Every mock provider prefixes its answer with `[mock <provider kind>]`, so
  # this matches regardless of which provider `COGNI_E2E_MODEL` selects.
  MOCK_SIGNATURE = /\[mock [a-z_]+\]/

  DEFAULT_TIMEOUT   = 60.seconds
  READY_TIMEOUT     = 90.seconds
  POLL_INTERVAL     = 200.milliseconds
  HTTP_TIMEOUT      = 15.seconds
  SHUTDOWN_TIMEOUT  = 10.seconds
  MAX_LOG_TAIL_SIZE = 8_000

  # Provider credentials must not be inherited by the children: the test has to
  # fail before any external request instead of silently hitting a real API.
  PROVIDER_API_KEY_VARS = %w[
    OPENAI_API_KEY
    OPENAI_BASE_URL
    CLIPROXY_API_KEY
    CLIPROXY_BASE_URL
    GONKA_API_KEY
    ANTHROPIC_API_KEY
    ANTHROPIC_AUTH_TOKEN
    GEMINI_API_KEY
    GOOGLE_GENERATIVE_AI_API_KEY
    GROQ_API_KEY
    OPENROUTER_API_KEY
    DEEPSEEK_API_KEY
    MISTRAL_API_KEY
    XAI_API_KEY
  ]

  # Ambient configuration that would otherwise leak the developer's checkout (or
  # a signature-verification override) into the isolated children.
  AMBIENT_CONFIG_VARS = %w[
    OCAWE_CONFIG_RCL
    OCAWE_PORT
    OCAWE_FEDERATION_SIGNATURES_REQUIRED
    OCAWE_FEDERATION_ACTOR_NAME
    OCAWE_FEDERATION_ACTOR_SUMMARY
    OCAWE_FEDERATION_ALIAS_URI
    OCAWE_FEDERATION_TAGS
    OCAWE_FEDERATION_RESOURCE_CONFORMS_TO
    OCAWE_FEDERATION_ACTION
    OCAWE_FEDERATION_PURPOSE
  ]

  class HarnessError < Exception
  end

  class TimeoutError < HarnessError
  end

  record HttpResult, status : Int32, content_type : String, body : String do
    def json : JSON::Any
      JSON.parse(body)
    end

    def json_object : Hash(String, JSON::Any)
      json.as_h? || raise HarnessError.new("expected a JSON object, got: #{body}")
    end

    def describe : String
      "HTTP #{status} #{content_type} #{body}"
    end
  end

  def model : String
    E2ETestHelpers.default_model
  end

  # Unique per run so a stale bundle, cached run or leftover outbox entry can
  # never satisfy an assertion (R-004).
  def unique_marker(label : String) : String
    "OCAWE-E2E-#{label}-#{Random::Secure.hex(8)}"
  end

  def runtime_binary : String
    configured = ENV[RUNTIME_BINARY_ENV]?.try(&.strip)
    relative = configured && !configured.empty? ? configured : DEFAULT_RUNTIME_BINARY
    path = File.expand_path(relative)

    unless File.exists?(path)
      raise HarnessError.new(<<-MESSAGE)
        Ocawe runtime binary not found at #{path}.

        This spec starts two real runtime processes, so the executable has to be
        built before the spec runs:

            #{RUNTIME_BUILD_COMMAND}

        Set #{RUNTIME_BINARY_ENV} to point at a different build if needed.
        MESSAGE
    end

    # `File.executable?` is deprecated on Crystal 1.19 while `File::Info.executable?`
    # does not exist on the oldest supported compiler (shard.yml: >= 1.12), so
    # check the permission bits directly.
    unless File.info(path).permissions.value & 0o111 != 0
      raise HarnessError.new("Ocawe runtime binary at #{path} is not executable; rebuild it with: #{RUNTIME_BUILD_COMMAND}")
    end

    path
  end

  def activity_headers : HTTP::Headers
    HTTP::Headers{"Accept" => ACTIVITY_CONTENT_TYPE}
  end

  def json_headers : HTTP::Headers
    HTTP::Headers{"Accept" => "application/json", "Content-Type" => "application/json"}
  end

  def http_get(url : String, headers : HTTP::Headers? = nil, timeout : Time::Span = HTTP_TIMEOUT) : HttpResult
    with_client(url, timeout) { |client, target| client.get(target, headers: headers) }
  end

  def http_post(url : String, body : String, headers : HTTP::Headers? = nil, timeout : Time::Span = HTTP_TIMEOUT) : HttpResult
    with_client(url, timeout) { |client, target| client.post(target, headers: headers, body: body) }
  end

  # Builds the outbound `Create(Ticket)` with Aptok's own ActivityPub/ForgeFed
  # vocabulary (`Aptok.forgefed_ticket` + `Aptok.create` under the hood), so the
  # spec never hand-writes an activity shape or a JSON-LD context (R-007).
  #
  # `Aptok.object` stamps the ActivityStreams context on the envelope; the
  # ForgeFed context is added next to it because the envelope carries a ForgeFed
  # `Ticket`.
  def build_ticket_activity(publish : Aptok::PublishRequest, delivery : Aptok::DeliveryConfig) : Aptok::JsonMap
    activity = Aptok::Transport.new(object_type: "Ticket").build_forgefed_ticket_create(publish, delivery)
    activity["@context"] = Aptok.json([Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT])
    activity
  end

  # Delivers through `Aptok::Transport`, the same egress path the runtime uses
  # for its own outbound activities: it applies the ActivityPub content types
  # and signs with the production HTTP Signature primitive (`draft-cavage`
  # `rsa-sha256`). Passing `key_pair: nil` produces the unsigned delivery the
  # negative control needs.
  #
  # `deliver!` raises on any non-2xx status, but a rejected delivery is an
  # expected outcome here, so the raw response is captured through the
  # transport's `detailed_post_provider` hook and returned either way.
  def deliver(delivery : Aptok::DeliveryConfig, activity : Aptok::JsonMap, key_pair : Aptok::ActorKeyPair? = nil, timeout : Time::Span = HTTP_TIMEOUT) : HttpResult
    captured : HttpResult? = nil
    transport = Aptok::Transport.new(
      detailed_post_provider: ->(url : String, headers : HTTP::Headers, payload : String) do
        result = http_post(url, payload, headers: headers, timeout: timeout)
        captured = result
        Aptok::PostResponse.new(result.status, result.body)
      end
    )

    begin
      transport.deliver!(delivery, activity, key_pair)
    rescue ex : Aptok::DeliveryError
      # Non-2xx: the response itself is the assertion subject, so this is only
      # fatal when the transport never got as far as an HTTP response.
      raise HarnessError.new("Aptok could not deliver to #{delivery.inbox}: #{ex.message}") if captured.nil?
    end

    result = captured
    raise HarnessError.new("Aptok::Transport never posted to #{delivery.inbox}") if result.nil?
    result
  end

  # Bounded polling with an explicit deadline and short retries (R-012).
  #
  # The block returns `nil` once the condition holds, or a short string
  # describing the state it observed. That string is reported on timeout, so a
  # failure always says what the harness actually saw.
  def wait_until(description : String, timeout : Time::Span = DEFAULT_TIMEOUT, interval : Time::Span = POLL_INTERVAL, &block : -> String?) : Nil
    deadline = Ocawe::Utils::TimeCompat.monotonic + timeout
    attempts = 0
    reason = "never evaluated"

    loop do
      attempts += 1
      reason = begin
        block.call
      rescue ex
        "#{ex.class}: #{ex.message}"
      end
      return if reason.nil?
      break if Ocawe::Utils::TimeCompat.monotonic >= deadline
      sleep interval
    end

    raise TimeoutError.new("timed out after #{timeout} and #{attempts} attempts waiting for #{description}; last observed: #{reason}")
  end

  # Correlation filter for outbox assertions: a `Create` whose `Note` object
  # replies to `ticket_id`. Assertions must never depend on the position of an
  # activity in the collection or on the collection size (R-009).
  def notes_replying_to(activities : Array(JSON::Any), ticket_id : String) : Array(Hash(String, JSON::Any))
    activities.compact_map do |entry|
      activity = entry.as_h?
      next nil unless activity
      next nil unless activity["type"]?.try(&.as_s?) == "Create"
      object = activity["object"]?.try(&.as_h?)
      next nil unless object
      next nil unless object["type"]?.try(&.as_s?) == "Note"
      next nil unless object["inReplyTo"]?.try(&.as_s?) == ticket_id
      activity
    end
  end

  # Correlation filter for the current ForgeFed result contract: workflow
  # replies are Offer(Ticket) activities whose result Ticket points back to the
  # received ticket through `inReplyTo`.
  def result_tickets_replying_to(activities : Array(JSON::Any), ticket_id : String) : Array(Hash(String, JSON::Any))
    activities.compact_map do |entry|
      activity = entry.as_h?
      next nil unless activity
      next nil unless activity["type"]?.try(&.as_s?) == "Offer"
      result_ticket = activity["object"]?.try(&.as_h?)
      next nil unless result_ticket
      next nil unless result_ticket["type"]?.try(&.as_s?) == "Ticket"
      next nil unless result_ticket["inReplyTo"]?.try(&.as_s?) == ticket_id
      activity
    end
  end

  # Correlation filter for outbound assertions: a `Create` wrapping a `Ticket`
  # whose text carries `marker`. Like `notes_replying_to`, it never depends on
  # the position of an activity in the collection (R-009).
  def tickets_containing(activities : Array(JSON::Any), marker : String) : Array(Hash(String, JSON::Any))
    activities.compact_map do |entry|
      activity = entry.as_h?
      next nil unless activity
      next nil unless activity["type"]?.try(&.as_s?) == "Create"
      object = activity["object"]?.try(&.as_h?)
      next nil unless object
      next nil unless object["type"]?.try(&.as_s?) == "Ticket"
      next nil unless object["content"]?.try(&.as_s?).to_s.includes?(marker)
      activity
    end
  end

  # Deliberate bounded wait used *only* before negative assertions ("nothing
  # else happened"). Polling cannot prove absence, so the harness instead gives
  # the receiver's federation poller several full cycles and then asserts the
  # state is unchanged. Positive waits all go through `wait_until`.
  def settle(duration : Time::Span) : Nil
    sleep duration
  end

  # Reserves a loopback port by letting the OS pick a free one. Ports must never
  # be hardcoded so two peers (and parallel CI jobs) cannot collide (R-002/R-003).
  def free_loopback_port : Int32
    server = TCPServer.new("127.0.0.1", 0)
    begin
      server.local_address.port
    ensure
      server.close
    end
  end

  private def with_client(url : String, timeout : Time::Span, &block : (HTTP::Client, String) -> HTTP::Client::Response) : HttpResult
    uri = URI.parse(url)
    client = HTTP::Client.new(uri)
    client.connect_timeout = timeout
    client.read_timeout = timeout
    begin
      response = block.call(client, uri.request_target)
      HttpResult.new(response.status_code, response.content_type.to_s, response.body.to_s)
    ensure
      client.close
    end
  end

  # One isolated Ocawe runtime process plus the temporary bundle it serves.
  class Peer
    # Matches `federation.s2s_poll_interval_seconds` in the generated Cawfile.
    POLL_INTERVAL_SECONDS = 1

    getter label : String
    getter workflow_id : String
    # ActivityPub actor identifier. It is derived from the Cawfile `#+name:`
    # header and therefore need not equal the workflow id.
    getter actor_name : String
    getter agent_name : String
    getter root : String
    getter port : Int32
    getter stdout_path : String
    getter stderr_path : String

    @process : Process?
    @stdout_file : File?
    @stderr_file : File?

    def initialize(@label : String, @workflow_id : String, @agent_name : String, @root : String, @port : Int32, actor_name : String? = nil)
      @actor_name = actor_name || @workflow_id
      @stdout_path = File.join(@root, "runtime-stdout.log")
      @stderr_path = File.join(@root, "runtime-stderr.log")
    end

    def base_url : String
      "http://127.0.0.1:#{@port}"
    end

    def actor_url : String
      "#{base_url}/actors/#{@actor_name}"
    end

    def inbox_url : String
      "#{actor_url}/inbox"
    end

    def outbox_url : String
      "#{actor_url}/outbox"
    end

    def key_id : String
      "#{actor_url}#main-key"
    end

    def private_key_path : String
      File.join(@root, "federation-private.pem")
    end

    def pid : Int64
      process = @process
      raise HarnessError.new("peer #{@label} is not running") unless process
      process.pid.to_i64
    end

    def running? : Bool
      process = @process
      !process.nil? && !process.terminated?
    end

    # Key pair used by the spec to sign outbound activities as this peer. Only
    # the private key *path* is handed to Aptok; the PEM itself is never read
    # into the spec process and never logged (S5/S6).
    def signing_key_pair : Aptok::ActorKeyPair
      Aptok::ActorKeyPair.new(
        id: key_id,
        owner: actor_url,
        public_key_pem: "",
        private_key_path: private_key_path,
      )
    end

    # Committed example bundle to run instead of the generated one. When set,
    # `write_bundle!` copies that directory into the temp root and rewrites the
    # demo ports/actor URLs through `substitutions`, so the spec exercises the
    # example that ships in the repository rather than a private copy of it.
    property example_source : String?
    property substitutions = {} of String => String
    # Extra environment for the child, used to pin `@name@fedi.internal` peers
    # to the loopback ports this run happens to have been given.
    property extra_env = {} of String => String

    # Writes the temporary workflow bundle: a root Cawfile plus one agent
    # markdown file, and generates a fresh RSA key under the temp root (R-003).
    def write_bundle! : Nil
      if source = @example_source
        copy_example_bundle!(source)
        return
      end

      Dir.mkdir_p(File.join(@root, "agents"))
      generate_private_key!
      File.write(File.join(@root, "Cawfile"), cawfile_source)
      File.write(File.join(@root, "agents", "#{@agent_name}.md"), agent_source)
    end

    # Copies the committed example verbatim (permissions included, so the exec
    # tool stays executable) and then applies the per-run substitutions. Every
    # substitution must match somewhere: if the example is edited so that a
    # placeholder disappears, the spec fails loudly instead of silently testing
    # the demo ports.
    private def copy_example_bundle!(source : String) : Nil
      unless Dir.exists?(source)
        raise HarnessError.new("example bundle for peer #{@label} not found at #{source}")
      end

      copy_tree(source, @root)
      # No key is generated here on purpose: the example declares none, so the
      # runtime has to generate its own signing key on first use.

      unmatched = [] of String
      @substitutions.each do |needle, _|
        unmatched << needle unless bundle_files.any? { |path| File.read(path).includes?(needle) }
      end
      unless unmatched.empty?
        raise HarnessError.new(
          "the committed example at #{source} no longer contains #{unmatched.join(", ")}; " \
          "update spec/e2e/activitypub_cawfile_send_spec.cr together with the example"
        )
      end

      bundle_files.each do |path|
        content = File.read(path)
        rewritten = content
        @substitutions.each { |needle, replacement| rewritten = rewritten.gsub(needle, replacement) }
        File.write(path, rewritten) unless rewritten == content
      end
    end

    private def copy_tree(source : String, destination : String) : Nil
      Dir.mkdir_p(destination)
      Dir.each_child(source) do |child|
        from = File.join(source, child)
        to = File.join(destination, child)
        if Dir.exists?(from)
          copy_tree(from, to)
        else
          File.copy(from, to)
        end
      end
    end

    # Text files of the copied bundle. Log files and the generated key are
    # excluded: the PEM must never be read or rewritten by the spec (S5/S6).
    private def bundle_files : Array(String)
      files = [] of String
      collect_files(@root, files)
      files.reject do |path|
        path == private_key_path || path.ends_with?(".log") || path.ends_with?(".pem")
      end
    end

    private def collect_files(directory : String, accumulator : Array(String)) : Nil
      Dir.each_child(directory) do |child|
        path = File.join(directory, child)
        Dir.exists?(path) ? collect_files(path, accumulator) : accumulator << path
      end
    end

    def start!(binary : String) : Nil
      raise HarnessError.new("peer #{@label} is already running") if @process

      stdout_file = File.open(@stdout_path, "w")
      stderr_file = File.open(@stderr_path, "w")
      @stdout_file = stdout_file
      @stderr_file = stderr_file

      @process = Process.new(
        binary,
        args: ["--port", @port.to_s, "--log-level", child_log_level],
        chdir: @root,
        env: child_env,
        clear_env: false,
        input: Process::Redirect::Close,
        output: stdout_file,
        error: stderr_file,
      )
    end

    def wait_until_ready!(timeout : Time::Span = READY_TIMEOUT) : Nil
      FederationE2E.wait_until("peer #{@label} to answer GET #{base_url}/health", timeout: timeout) do
        ensure_alive!
        result = FederationE2E.http_get("#{base_url}/health")
        result.status == 200 ? nil : result.describe
      end

      FederationE2E.wait_until("peer #{@label} to publish its actor document at #{actor_url}", timeout: timeout) do
        ensure_alive!
        result = FederationE2E.http_get(actor_url, headers: FederationE2E.activity_headers)
        next result.describe unless result.status == 200
        document = result.json.as_h?
        next "actor response is not a JSON object: #{result.body}" unless document
        next "actor document has no publicKey yet: #{result.body}" unless document["publicKey"]?
        nil
      end
    end

    # Fails fast instead of burning the whole polling deadline when the runtime
    # died on startup (bad bundle, port clash, missing openssl, ...).
    def ensure_alive! : Nil
      process = @process
      raise HarnessError.new("peer #{@label} was never started") unless process
      return unless process.terminated?

      raise HarnessError.new("peer #{@label} exited before becoming ready.\n#{diagnostics}")
    end

    def stop! : Nil
      if process = @process
        terminate_process(process)
        @process = nil
      end

      @stdout_file.try(&.close) rescue nil
      @stderr_file.try(&.close) rescue nil
      @stdout_file = nil
      @stderr_file = nil
    end

    # Removes the whole temporary root, including the private key (R-013/S5/S6).
    def remove_root! : Nil
      FileUtils.rm_rf(@root)
    end

    def diagnostics : String
      String.build do |io|
        io << "--- peer " << @label << " (workflow " << @workflow_id << ") ---\n"
        io << "  root:   " << @root << '\n'
        io << "  actor:  " << actor_url << '\n'
        io << "  pid:    " << (@process.try(&.pid) || "n/a") << '\n'
        io << "  alive:  " << running? << '\n'
        io << "  stdout (" << @stdout_path << "):\n"
        io << indent(log_tail(@stdout_path))
        io << "  stderr (" << @stderr_path << "):\n"
        io << indent(log_tail(@stderr_path))
      end
    end

    private def terminate_process(process : Process) : Nil
      begin
        process.terminate unless process.terminated?
      rescue
        # Already gone between the check and the signal.
      end

      unless await_exit(process, SHUTDOWN_TIMEOUT)
        begin
          process.terminate(graceful: false)
        rescue
          # Already gone.
        end
        await_exit(process, SHUTDOWN_TIMEOUT)
      end

      begin
        process.wait
      rescue
        # The process was already reaped.
      end
    end

    private def await_exit(process : Process, timeout : Time::Span) : Bool
      deadline = Ocawe::Utils::TimeCompat.monotonic + timeout
      until process.terminated?
        return false if Ocawe::Utils::TimeCompat.monotonic >= deadline
        sleep 50.milliseconds
      end
      true
    end

    private def child_log_level : String
      ENV["OCAWE_E2E_CHILD_LOG_LEVEL"]?.try(&.strip).presence || "warning"
    end

    private def child_env : Hash(String, String?)
      env = {} of String => String?
      # `nil` removes the variable from the child environment.
      FederationE2E::PROVIDER_API_KEY_VARS.each { |name| env[name] = nil }
      FederationE2E::AMBIENT_CONFIG_VARS.each { |name| env[name] = nil }
      env["COGNICORE_MOCK_LLM"] = "1"
      env["COGNI_E2E_MODEL"] = FederationE2E.model
      env["OCAWE_WORKFLOWS_ROOT"] = @root
      extra_env.each { |name, value| env[name] = value }
      env
    end

    private def generate_private_key! : Nil
      errors = IO::Memory.new
      status = Process.run(
        "openssl",
        args: ["genrsa", "-out", private_key_path, "2048"],
        output: Process::Redirect::Close,
        error: errors,
      )
      unless status.success?
        raise HarnessError.new("openssl genrsa failed for peer #{@label}: #{errors.to_s.strip}")
      end
      File.chmod(private_key_path, 0o600)
    end

    # `federation.allow_private_address` is what makes loopback federation work:
    # Aptok's default document loader refuses to dereference private addresses,
    # which would block resolving the peer's public key during inbound signature
    # verification. `signatures_required` stays `true` — the success path must
    # go through real HTTP Signature verification.
    #
    # `s2s_poll_interval_seconds` has to be small because queued inbox
    # activities are drained by the federation poller.
    #
    # The output struct deliberately does not include `Api::Federation::Outbox`:
    # that name is special-cased in `build_output_from_state` and would replace
    # the agent's own output with an empty OrderedCollection.
    private def cawfile_source : String
      <<-CAWFILE
      # Temporary bundle generated by spec/e2e/federation_e2e_helper.cr.
      # Ports, actor URLs and keys are generated per run and never committed.
      settings do
        data.adapter = "memory"
        federation.local_actor = "#{actor_url}"
        federation.local_key_id = "#{key_id}"
        federation.local_private_key_path = "#{private_key_path}"
        federation.signatures_required = true
        federation.s2s_poll_interval_seconds = #{POLL_INTERVAL_SECONDS}
        federation.allow_private_address = true
      end

      struct FederationInput
        include Api::Federation::Inbox
      end

      struct AgentOutput
        include Api::MastraAPI::Response
      end

      @[Validate(FederationInput, AgentOutput)]
      @[Model("#{FederationE2E.model}")]
      workflow "#{@workflow_id}" do
        agent "#{@agent_name}"
      end

      CAWFILE
    end

    private def agent_source : String
      <<-AGENT
      ---
      name: "#{@label} agent"
      description: "E2E federation peer #{@label}"
      ---

      You are the #{@label} agent of the Ocawe ActivityPub two-agent E2E test.
      Answer with a single short sentence and repeat every marker you are given.

      #+begin_src crystal schema:input
      Schema::Types.object({"input" => Schema::Types.any()}, strict: false)
      #+end_src

      #+begin_src crystal schema:output
      Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
      #+end_src

      AGENT
    end

    private def log_tail(path : String) : String
      return "    <no log file>\n" unless File.exists?(path)
      content = File.read(path)
      return "    <empty>\n" if content.empty?
      content = "...\n" + content[(content.size - MAX_LOG_TAIL_SIZE)..] if content.size > MAX_LOG_TAIL_SIZE
      content.ends_with?('\n') ? content : content + "\n"
    end

    private def indent(text : String) : String
      # `String#lines` chomps by default, so the terminators have to be restored
      # explicitly - otherwise the whole child log collapses onto one line and
      # the diagnostics required by AC-009 become unreadable.
      text.lines.map { |line| "    #{line}\n" }.join
    end
  end

  # Owns both peers and guarantees cleanup on success and failure (R-013).
  class Harness
    getter sender : Peer
    getter receiver : Peer
    # Per-run marker injected into the example's published content, so the
    # correlated note can be attributed to this run and not to a leftover.
    getter marker : String = ""

    # Runs the committed `caws/13-activitypub` example instead of the bundle the
    # harness generates. The two peers keep their per-run temp roots, loopback
    # ports and freshly generated keys; only the workflow sources come from the
    # repository.
    def self.run_example(&block : Harness ->) : Nil
      run(example_root: "caws/13-activitypub", &block)
    end

    def self.run(example_root : String? = nil, &block : Harness ->) : Nil
      harness = example_root ? new_example(example_root) : new
      begin
        harness.start!
        block.call(harness)
      rescue ex
        # Assertion failures carry no runtime context, so dump both children's
        # logs before the temp roots are removed (R-012/AC-009).
        STDERR.puts
        STDERR.puts "ActivityPub two-agent E2E failed: #{ex.class}: #{ex.message}"
        STDERR.puts harness.diagnostics
        raise ex
      ensure
        harness.cleanup!
      end
    end

    # Demo values used by the committed example; rewritten per run.
    EXAMPLE_SENDER_WORKFLOW   = "13-activitypub-sender"
    EXAMPLE_RECEIVER_WORKFLOW = "13-activitypub-receiver"
    # `#+name:` of each example Cawfile, and therefore the actor identifier.
    EXAMPLE_SENDER_ACTOR   = "sender"
    EXAMPLE_RECEIVER_ACTOR = "receiver"
    # The content the sender publishes, used to carry a per-run marker.
    EXAMPLE_CONTENT = "Please review the federation docs."
    # Mirrors `Ocawe::Federation::InternalDomain::PEERS_ENV_VAR`; the harness
    # deliberately speaks only the public surface, so the name is repeated here.
    INTERNAL_PEERS_ENV = "OCAWE_FEDERATION_INTERNAL_PEERS"

    def self.new_example(example_root : String) : Harness
      run_id = Random::Secure.hex(6)
      sender = Peer.new(
        label: "sender",
        workflow_id: EXAMPLE_SENDER_WORKFLOW,
        actor_name: EXAMPLE_SENDER_ACTOR,
        agent_name: "sender",
        root: File.join(Dir.tempdir, "ocawe-e2e-cawfile-#{run_id}-sender"),
        port: FederationE2E.free_loopback_port,
      )
      receiver = Peer.new(
        label: "receiver",
        workflow_id: EXAMPLE_RECEIVER_WORKFLOW,
        actor_name: EXAMPLE_RECEIVER_ACTOR,
        agent_name: "receiver",
        root: File.join(Dir.tempdir, "ocawe-e2e-cawfile-#{run_id}-receiver"),
        port: FederationE2E.free_loopback_port,
      )

      # The example Cawfiles carry no host or port: the sender addresses the
      # receiver as `@receiver@fedi.internal`, which resolves through this peer
      # map. Only the loopback ports, which are assigned per run, are injected.
      marker = FederationE2E.unique_marker("cawfile")
      peers_env = "#{EXAMPLE_SENDER_ACTOR}=#{sender.base_url},#{EXAMPLE_RECEIVER_ACTOR}=#{receiver.base_url}"

      sender.example_source = File.join(example_root, "sender")
      sender.substitutions = {
        "port = 4111"     => "port = #{sender.port}",
        EXAMPLE_CONTENT => "#{EXAMPLE_CONTENT} Marker #{marker}.",
      }
      sender.extra_env = {INTERNAL_PEERS_ENV => peers_env}

      receiver.example_source = File.join(example_root, "receiver")
      receiver.substitutions = {
        "port = 4222" => "port = #{receiver.port}",
        # The example uses a real provider; the spec must stay offline.
        "@[Model(Kimi)]" => %(@[Model("#{FederationE2E.model}")]),
      }
      receiver.extra_env = {INTERNAL_PEERS_ENV => peers_env}

      new(sender, receiver, marker)
    end

    def initialize(@sender : Peer, @receiver : Peer, @marker : String = "")
    end

    def initialize
      run_id = Random::Secure.hex(6)
      @sender = Peer.new(
        label: "sender",
        workflow_id: "e2e-sender-#{run_id}",
        agent_name: "sender",
        root: File.join(Dir.tempdir, "ocawe-e2e-federation-#{run_id}-sender"),
        port: FederationE2E.free_loopback_port,
      )
      @receiver = Peer.new(
        label: "receiver",
        workflow_id: "e2e-receiver-#{run_id}",
        agent_name: "receiver",
        root: File.join(Dir.tempdir, "ocawe-e2e-federation-#{run_id}-receiver"),
        port: FederationE2E.free_loopback_port,
      )
    end

    def peers : Array(Peer)
      [@sender, @receiver]
    end

    # Several full poller cycles: long enough that a replayed or rejected
    # delivery would already have been processed if it were going to be.
    def receiver_poll_settle_time : Time::Span
      (Peer::POLL_INTERVAL_SECONDS * 4).seconds
    end

    def start! : Nil
      binary = FederationE2E.runtime_binary
      peers.each(&.write_bundle!)
      peers.each(&.start!(binary))
      peers.each(&.wait_until_ready!)
    end

    def cleanup! : Nil
      peers.each do |peer|
        begin
          peer.stop!
        rescue ex
          STDERR.puts "[federation-e2e] failed to stop peer #{peer.label}: #{ex.message}"
        end
      end
      peers.each do |peer|
        begin
          peer.remove_root!
        rescue ex
          STDERR.puts "[federation-e2e] failed to remove #{peer.root}: #{ex.message}"
        end
      end
    end

    # Same as `FederationE2E.wait_until`, but a timeout also carries both
    # children's logs so the failure is actionable without a rerun.
    def wait_until(description : String, timeout : Time::Span = DEFAULT_TIMEOUT, interval : Time::Span = POLL_INTERVAL, &block : -> String?) : Nil
      FederationE2E.wait_until(description, timeout: timeout, interval: interval, &block)
    rescue ex : TimeoutError
      raise TimeoutError.new("#{ex.message}\n#{diagnostics}")
    end

    def diagnostics : String
      peers.map(&.diagnostics).join("\n")
    end

    # Triggers a workflow through the supported classic run API and returns the
    # run snapshot. This is the existing public mechanism for starting a run
    # (R-006); it stays mounted next to the federation routes because enabling
    # `Api::Federation::Inbox` yields `api = ["classic", "federation"]`.
    def start_run(peer : Peer, prompt : String) : Hash(String, JSON::Any)
      body = {"input_data" => {"input" => {"content" => prompt}}}.to_json
      result = FederationE2E.http_post(
        "#{peer.base_url}/v1/workflows/#{peer.workflow_id}/runs",
        body,
        headers: FederationE2E.json_headers,
      )
      unless result.status == 201
        raise HarnessError.new("starting a run on peer #{peer.label} failed: #{result.describe}\n#{diagnostics}")
      end
      result.json_object
    end

    # Publicly observable run list (`GET /v1/workflows/:id/runs`). Used to prove
    # that the receiver executed exactly once, without reaching into private
    # state (R-008/R-016).
    def runs(peer : Peer) : Array(JSON::Any)
      result = FederationE2E.http_get("#{peer.base_url}/v1/workflows/#{peer.workflow_id}/runs")
      unless result.status == 200
        raise HarnessError.new("listing runs of peer #{peer.label} failed: #{result.describe}")
      end
      result.json_object["runs"]?.try(&.as_a?) || [] of JSON::Any
    end

    def actor_document(peer : Peer) : Hash(String, JSON::Any)
      result = FederationE2E.http_get(peer.actor_url, headers: FederationE2E.activity_headers)
      unless result.status == 200
        raise HarnessError.new("fetching the actor document of peer #{peer.label} failed: #{result.describe}\n#{diagnostics}")
      end
      result.json_object
    end

    # Walks the public outbox `OrderedCollectionPage` chain. Assertions
    # correlate on activity ids rather than on order or collection size (R-009),
    # but they still need the complete set to prove "exactly once".
    def outbox_activities(peer : Peer, max_pages : Int32 = 25) : Array(JSON::Any)
      activities = [] of JSON::Any
      next_url = "#{peer.outbox_url}?page=1"
      pages = 0

      while (url = next_url) && pages < max_pages
        result = FederationE2E.http_get(url, headers: FederationE2E.activity_headers)
        unless result.status == 200
          raise HarnessError.new("reading the outbox of peer #{peer.label} failed: GET #{url} -> #{result.describe}")
        end

        document = result.json_object
        items = document["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
        activities.concat(items)
        pages += 1
        break if items.empty?
        next_url = document["next"]?.try(&.as_s?)
      end

      activities
    end
  end
end
