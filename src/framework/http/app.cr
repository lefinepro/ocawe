require "kemal"
require "yaml"
require "../discovery/workflow_locator"
require "../agents/loader"
require "../skills/loader"
require "../cognicore/version"
require "../cognicore/config/acd_config"
require "../cognicore/schema/crystal_dsl"
require "../cognicore/workflow/run"
require "./endpoints/health"
require "./endpoints/docs"
require "./endpoints/workflows"
require "./endpoints/tools"
require "./endpoints/skills"
require "./endpoints/runs"
require "./endpoints/hitl"
require "./endpoints/compat"

module ACD
  module HTTP
    class App
      RELOAD_INTERVAL_SECONDS = 2.0

      def initialize(@port : Int32, workflows_root : String? = nil, fallback_workflows_root : String? = nil)
        config = CogniCore::Config::ACDConfig.settings.workflows
        preferred_root = workflows_root || config.preferred_workflows_root
        fallback_root = fallback_workflows_root || config.fallback_workflows_root
        @locator = Discovery::WorkflowLocator.new(preferred_root, fallback_root)
        @agent_loader = Agents::Loader.new
        @skill_loader = Skills::Loader.new
        @workflow_engine = CogniCore::Workflow::Engine.new
        @workflow_service = CogniCore::Workflow::Service.new(@workflow_engine)
        @workflow_ids = [] of String
        @workflow_index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
        )
        @skills_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          file_path: String,
        )
        @tools_index = [] of NamedTuple(
          id: String,
          workflow_id: String,
        )
        @cache_lock = Mutex.new
      end

      def start
        reload_cache!
        start_reload_watcher

        Kemal.config.port = @port
        mount_health_endpoints
        mount_docs_endpoints
        mount_workflow_endpoints
        mount_tool_endpoints
        mount_skill_endpoints
        mount_run_endpoints
        mount_hitl_endpoints
        mount_compat_endpoints

        Kemal.run
      end

      private def start_reload_watcher
        fingerprint = current_fingerprint
        spawn do
          loop do
            sleep RELOAD_INTERVAL_SECONDS
            current = current_fingerprint
            next if current == fingerprint

            begin
              reload_cache!
              fingerprint = current
              puts "[cognicore] workflow cache reloaded"
            rescue ex
              STDERR.puts "[cognicore] workflow cache reload failed: #{ex.message}"
            end
          end
        end
      end

      private def reload_cache!
        bundles = @locator.list_workflows
        rebuilt_engine = CogniCore::Workflow::Engine.new
        ids = [] of String
        index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
        )
        skills_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          file_path: String,
        )
        tools_index = [] of NamedTuple(
          id: String,
          workflow_id: String,
        )

        bundles.each do |bundle|
          global_agents = @agent_loader.load_dir("./agents")
          loaded_agents = merge_agents(global_agents, @agent_loader.load_dir(bundle.agents_dir))
          loaded_skills = @skill_loader.load_dir(bundle.skills_dir)

          ids << bundle.id
          definition = load_workflow_definition(bundle, loaded_agents)
          rebuilt_engine.register(definition)
          tool_ids = definition.nodes.select { |node| node.kind == CogniCore::Workflow::NodeKind::Tool }.map(&.id)

          loaded_skills.each do |skill|
            qualified_id = "#{bundle.id}:#{skill.id}"
            skills_index[qualified_id] = {
              id: qualified_id,
              workflow_id: bundle.id,
              name: skill.name,
              description: skill.description,
              file_path: skill.file_path,
            }
          end

          tool_ids.each do |tool_id|
            tools_index << {
              id: tool_id,
              workflow_id: bundle.id,
            }
          end

          index[bundle.id] = {
            source_root_type: bundle.source_root_type,
            workflow_file: bundle.workflow_file,
            agents: loaded_agents.map(&.id),
            skills: loaded_skills.map(&.id),
            tools: tool_ids,
            default_model: definition.default_model,
          }
        end

        @cache_lock.synchronize do
          @workflow_ids = ids
          @workflow_index = index
          @skills_index = skills_index
          @tools_index = tools_index
          @workflow_engine = rebuilt_engine
          @workflow_service = CogniCore::Workflow::Service.new(@workflow_engine)
        end
      end

      private def workflow_ids : Array(String)
        @cache_lock.synchronize { @workflow_ids.dup }
      end

      private def workflow_by_id(workflow_id : String)
        @cache_lock.synchronize { @workflow_index[workflow_id]? }
      end

      private def tools : Array(NamedTuple(id: String, workflow_id: String))
        @cache_lock.synchronize { @tools_index.dup }
      end

      private def skills : Array(NamedTuple(id: String, workflow_id: String, name: String, description: String, file_path: String))
        @cache_lock.synchronize { @skills_index.values.to_a }
      end

      private def skill_by_id(skill_id : String)
        @cache_lock.synchronize { @skills_index[skill_id]? }
      end

      private def merge_agents(
        global_agents : Array(ACD::Agents::LoadedAgent),
        local_agents : Array(ACD::Agents::LoadedAgent)
      ) : Array(ACD::Agents::LoadedAgent)
        merged = {} of String => ACD::Agents::LoadedAgent
        global_agents.each { |agent| merged[agent.id] = agent }
        local_agents.each { |agent| merged[agent.id] = agent }
        merged.values.to_a
      end

      private def current_fingerprint : String
        bundles = @locator.list_workflows
        file_count = 0
        latest_mtime = 0_i64

        global_files = [] of String
        global_files.concat(glob_files("./agents", "*.md"))
        global_files.concat(glob_files("./tools", "*"))

        global_files.each do |path|
          next unless File.exists?(path)
          file_count += 1
          mtime = File.info(path).modification_time.to_unix_ms
          latest_mtime = mtime if mtime > latest_mtime
        end

        bundles.each do |bundle|
          files = [bundle.workflow_file] of String
          files.concat(glob_files(bundle.agents_dir, "*.md"))
          files.concat(glob_files(bundle.skills_dir, "*.md"))
          files.concat(glob_files(File.join(bundle.root_path, "tools"), "*"))

          files.each do |path|
            next unless File.exists?(path)
            file_count += 1
            mtime = File.info(path).modification_time.to_unix_ms
            latest_mtime = mtime if mtime > latest_mtime
          end
        end

        "#{bundles.size}:#{file_count}:#{latest_mtime}"
      end

      private def glob_files(root : String, pattern : String) : Array(String)
        return [] of String unless Dir.exists?(root)

        paths = [] of String
        Dir.glob(File.join(root, pattern)) do |path|
          paths << path if File.file?(path)
        end
        paths
      end

      private def not_implemented(env, message : String) : String
        env.response.status_code = 501
        env.response.content_type = "application/json"
        {error: {type: "not_implemented", message: message}}.to_json
      end

      private def json_body(env) : CogniCore::Workflow::AnyHash
        raw = env.request.body.try(&.gets_to_end).to_s
        return {} of String => JSON::Any if raw.strip.empty?
        parsed = JSON.parse(raw)
        parsed.as_h? || {} of String => JSON::Any
      rescue
        {} of String => JSON::Any
      end

      private def parse_node_selector(value : JSON::Any?) : (String | Array(String) | Nil)
        return nil unless value
        if as_string = value.as_s?
          return as_string
        end
        if as_array = value.as_a?
          return as_array.compact_map(&.as_s?)
        end
        nil
      end

      private def with_workflow_errors(env, &block : -> T) : (T | String) forall T
        block.call
      rescue ex
        message = ex.message || "workflow request failed"
        if message.includes?("unknown workflow") || message.includes?("unknown workflow bundle")
          env.response.status_code = 404
          env.response.content_type = "application/json"
          return {error: {type: "not_found", message: message}}.to_json
        end
        if message.includes?("unknown node") || message.includes?("requires node")
          env.response.status_code = 400
          env.response.content_type = "application/json"
          return {error: {type: "bad_request", message: message}}.to_json
        end
        env.response.status_code = 422
        env.response.content_type = "application/json"
        return {error: {type: "workflow_error", message: message}}.to_json
      end

      private def load_workflow_definition(bundle : Discovery::WorkflowBundle, loaded_agents : Array(Agents::LoadedAgent)) : CogniCore::Workflow::WorkflowDefinition
        workflow = CogniCore::Workflow.create_workflow(bundle.id, "Loaded from #{bundle.workflow_file}")
        agent_index = {} of String => Agents::LoadedAgent
        loaded_agents.each { |agent| agent_index[agent.id] = agent }
        last_agent_id = nil.as(String?)

        crystal_tool_pattern = /^\s*tool\s+(tool_[A-Za-z0-9_]+)\s*$/
        external_tool_pattern = /^\s*tool\s+"([^"]+)"\s*,\s*runtime:\s*(\{.*\})\s*$/
        skill_pattern = /^\s*skill\s+"([^"]+)"(?:\s*,\s*agent:\s*"([^"]+)")?/
        rag_pattern = /^\s*rag\s+"([^"]+)"(?:\s*,\s*config:\s*(\{.*\}))?/
        approve_pattern = /^\s*approve\s+"([^"]+)"(?:\s*,\s*reason:\s*"([^"]+)")?/

        File.each_line(bundle.workflow_file) do |raw|
          line = raw.strip
          next if line.empty? || line.starts_with?("#")

          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = agent_index[agent_id]?
            params = parse_line_params(tail, bundle.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)

            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: bundle.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: bundle.workflow_file,
              agent_id: agent_id
            )

            workflow.agent(
              agent_id,
              prompt: prompt,
              model: model,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
            )
            last_agent_id = agent_id
            next
          end
          if match = line.match(/^\s*use_model\s+"([^"]+)"/)
            workflow.use_model(match[1])
            next
          end
          if match = line.match(skill_pattern)
            workflow.skill(match[1], agent: match[2]?)
            next
          end
          if match = line.match(/^\s*voice\s+"([^"]+)"(.*)$/)
            voice_id = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, bundle.workflow_file, "voice #{voice_id}")

            inline_config = params["config"]?.try { |value| parse_runtime_object(value, bundle.workflow_file) } || ({} of String => JSON::Any)
            requested_agent_id = parse_optional_string(params["agent"]?) || last_agent_id
            agent_voice = requested_agent_id.try { |id| agent_index[id]?.try(&.voice_config) } || ({} of String => JSON::Any)
            config = agent_voice.merge(inline_config) { |_k, _left, right| right }

            workflow.voice(voice_id, config: config)
            next
          end
          if match = line.match(rag_pattern)
            config = match[2]? ? parse_runtime_object(match[2], bundle.workflow_file) : ({} of String => JSON::Any)
            workflow.rag(match[1], config: config)
            next
          end
          if match = line.match(crystal_tool_pattern)
            workflow.tool(match[1])
            next
          end
          if match = line.match(external_tool_pattern)
            runtime = parse_runtime_object(match[2], bundle.workflow_file)
            workflow.tool(match[1], runtime: runtime, workflow_root: bundle.root_path)
            next
          end
          if line.starts_with?("tool ")
            raise "#{bundle.workflow_file}: unsupported tool syntax '#{line}'. Use `tool tool_*` or `tool \"path\", runtime: { ... }`"
          end
          if match = line.match(approve_pattern)
            workflow.approve(match[1], reason: match[2]? || "human approval required")
            next
          end
          if match = line.match(/^\s*custom\s+"([^"]+)"/)
            workflow.custom(match[1]) { |_ctx| CogniCore::Workflow::WorkflowNodeResult.continue }
            next
          end
        end

        workflow.commit
      end

      private def resolve_agent_schema(
        literal : String?,
        loaded : Agents::LoadedAgent?,
        kind : String,
        workflow_file : String,
        agent_id : String
      ) : CogniCore::Schema::Validator?
        if literal
          stripped = literal.strip
          if match = stripped.match(/^schema_ref\("([^"]+)"\)$/)
            ref_name = match[1]
            schema_source = case ref_name
                            when "input"
                              loaded.try(&.input_schema_dsl)
                            when "output"
                              loaded.try(&.output_schema_dsl)
                            else
                              raise "#{workflow_file}: unknown schema_ref(\"#{ref_name}\") for agent #{agent_id}"
                            end
            raise "#{workflow_file}: schema_ref(\"#{ref_name}\") missing in agent #{agent_id} markdown" unless schema_source
            return CogniCore::Schema::CrystalDSL.compile(schema_source, "#{workflow_file}: agent #{agent_id} #{kind} schema_ref")
          end

          return CogniCore::Schema::CrystalDSL.compile(stripped, "#{workflow_file}: agent #{agent_id} #{kind} schema")
        end

        fallback = kind == "input" ? loaded.try(&.input_schema_dsl) : loaded.try(&.output_schema_dsl)
        return nil unless fallback
        CogniCore::Schema::CrystalDSL.compile(fallback, "#{workflow_file}: agent #{agent_id} #{kind} markdown schema")
      end

      private def parse_line_params(tail : String, workflow_file : String, context : String) : Hash(String, String)
        params = {} of String => String
        stripped = tail.strip
        return params if stripped.empty?

        working = stripped
        working = working[1..] if working.starts_with?(",")
        pieces = split_top_level_params(working)
        pieces.each do |piece|
          next if piece.strip.empty?
          separator = piece.index(':')
          raise "#{workflow_file}: invalid #{context} param '#{piece}'" unless separator
          key = piece[0, separator].strip
          value = piece[separator + 1, piece.size - separator - 1].strip
          raise "#{workflow_file}: invalid #{context} param '#{piece}'" if key.empty? || value.empty?
          params[key] = value
        end
        params
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

      private def parse_optional_string(literal : String?) : String?
        return nil unless literal
        return nil unless literal.starts_with?('"') && literal.ends_with?('"') && literal.size >= 2
        literal[1, literal.size - 2]
      end

      private def parse_runtime_object(literal : String, workflow_file : String) : CogniCore::Workflow::AnyHash
        parsed = YAML.parse(literal)
        hash = JSON.parse(parsed.to_json).as_h?
        raise "#{workflow_file}: runtime must be an object: #{literal}" unless hash
        hash
      rescue ex
        raise "#{workflow_file}: invalid runtime object '#{literal}': #{ex.message}"
      end

      private def openapi_document : String
        {
          "openapi" => "3.0.3",
          "info" => {
            "title" => "CogniCore API",
            "version" => CogniCore::VERSION,
            "description" => "Current HTTP API surface with scaffolded workflow endpoints.",
          },
          "servers" => [
            {"url" => "http://localhost:#{@port}"},
          ],
          "tags" => [
            {"name" => "System"},
            {"name" => "Workflows"},
            {"name" => "Tools"},
            {"name" => "Skills"},
            {"name" => "Runs"},
            {"name" => "HITL"},
            {"name" => "Compat"},
          ],
          "paths" => {
            "/health" => {
              "get" => {
                "tags" => ["System"],
                "summary" => "Health check",
                "responses" => {
                  "200" => {
                    "description" => "Server health",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/HealthResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "List workflow IDs",
                "responses" => {
                  "200" => {
                    "description" => "Workflow id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {
                          "type" => "array",
                          "items" => {"type" => "string"},
                        },
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "Get workflow metadata",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Workflow metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/WorkflowResponse"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/tools" => {
              "get" => {
                "tags" => ["Tools"],
                "summary" => "List discovered tools",
                "responses" => {
                  "200" => {
                    "description" => "Tool list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/ToolListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/skills" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "List discovered skills",
                "responses" => {
                  "200" => {
                    "description" => "Skill list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/skills/{skillId}" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "Get skill metadata",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillItem"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/skills/{skillId}/execute" => {
              "post" => {
                "tags" => ["Skills"],
                "summary" => "Execute skill (scaffold)",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill execution response",
                    "content" => {
                      "application/json" => {
                        "schema" => {"type" => "object"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/responses" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI responses compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/chat/completions" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI chat completions compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Start workflow run (scaffold)",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
              "get" => {
                "tags" => ["Runs"],
                "summary" => "List runs for workflow",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}" => {
              "get" => {
                "tags" => ["Runs"],
                "summary" => "Get run snapshot (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/resume" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Resume run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/restart" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Restart run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/time-travel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Time travel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/cancel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Cancel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "List HITL runs",
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "Get HITL run details (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}/actions" => {
              "post" => {
                "tags" => ["HITL"],
                "summary" => "Apply HITL action (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
          },
          "components" => {
            "parameters" => {
              "WorkflowId" => {
                "name" => "workflowId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
              "RunId" => {
                "name" => "runId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
            },
            "responses" => {
              "NotImplemented" => {
                "description" => "Endpoint scaffold is not implemented yet",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                    "example" => {
                      "error" => {
                        "type" => "not_implemented",
                        "message" => "endpoint pending implementation",
                      },
                    },
                  },
                },
              },
              "NotFound" => {
                "description" => "Resource not found",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                  },
                },
              },
            },
            "schemas" => {
              "HealthResponse" => {
                "type" => "object",
                "required" => ["status", "timestamp"],
                "properties" => {
                  "status" => {"type" => "string", "example" => "ok"},
                  "timestamp" => {"type" => "string"},
                },
              },
              "WorkflowResponse" => {
                "type" => "object",
                "required" => ["workflow_id", "source_root_type", "workflow_file", "agents", "skills", "tools"],
                "properties" => {
                  "workflow_id" => {"type" => "string"},
                  "source_root_type" => {"type" => "string"},
                  "workflow_file" => {"type" => "string"},
                  "agents" => {"type" => "array", "items" => {"type" => "string"}},
                  "skills" => {"type" => "array", "items" => {"type" => "string"}},
                  "tools" => {"type" => "array", "items" => {"type" => "string"}},
                  "default_model" => {"type" => "string", "nullable" => true},
                },
              },
              "ToolItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                },
              },
              "ToolListResponse" => {
                "type" => "object",
                "required" => ["tools"],
                "properties" => {
                  "tools" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/ToolItem"}},
                },
              },
              "SkillItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id", "name", "description", "file_path"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                  "name" => {"type" => "string"},
                  "description" => {"type" => "string"},
                  "file_path" => {"type" => "string"},
                },
              },
              "SkillListResponse" => {
                "type" => "object",
                "required" => ["skills"],
                "properties" => {
                  "skills" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/SkillItem"}},
                },
              },
              "RunListResponse" => {
                "type" => "object",
                "required" => ["runs"],
                "properties" => {
                  "runs" => {"type" => "array", "items" => {"type" => "string"}},
                },
              },
              "ErrorEnvelope" => {
                "type" => "object",
                "required" => ["error"],
                "properties" => {
                  "error" => {
                    "type" => "object",
                    "required" => ["type", "message"],
                    "properties" => {
                      "type" => {"type" => "string"},
                      "message" => {"type" => "string"},
                    },
                  },
                },
              },
            },
          },
        }.to_json
      end

      private def swagger_ui_html : String
        <<-HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>CogniCore API Docs</title>
            <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script>
              window.ui = SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: "#swagger-ui"
              });
            </script>
          </body>
        </html>
        HTML
      end
    end
  end
end
