module CogniDockerGit
  module AppConfig
    extend self

    def project_root : String
      File.expand_path("..", __DIR__)
    end

    def workflows_root : String
      File.join(project_root, "workflows")
    end

    def settings : Cogni::Config::Settings
      Cogni::Config::Settings.new(
        workflows: Cogni::Config::WorkflowSettings.new(
          preferred_workflows_root: workflows_root,
          fallback_workflows_root: workflows_root,
        ),
        functions: {
          "docker_workspace_create" => docker_workspace_create,
          "docker_workspace_clone" => docker_workspace_clone,
          "docker_workspace_open" => docker_workspace_open,
          "docker_workspace_delete" => docker_workspace_delete,
        } of String => Cogni::Workflow::FunctionHandler,
        workspace_bootstrap: -> : Nil { CogniDockerGit.bootstrap_workspace_extensions! },
      )
    end

    private def docker_workspace_create : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        workspace = current_workspace(ctx)
        workspace_id = "ws_#{Time.utc.to_unix_ms}"
        repo = workspace["repo"]?.try(&.as_s?) || "none"
        {
          "workspace_id" => JSON.parse(workspace_id.to_json),
          "workspace_repo" => JSON.parse(repo.to_json),
          "workspace_action" => JSON.parse("create".to_json),
          "workspace" => JSON.parse(workspace.to_json),
        }
      end
    end

    private def docker_workspace_clone : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        workspace = current_workspace(ctx)
        workspace_id = workspace_id_from_ctx(ctx)
        branch = workspace["branch"]?.try(&.as_s?) || "default"
        {
          "workspace_id" => JSON.parse(workspace_id.to_json),
          "workspace_branch" => JSON.parse(branch.to_json),
          "workspace_action" => JSON.parse("clone".to_json),
          "workspace" => JSON.parse(workspace.to_json),
        }
      end
    end

    private def docker_workspace_open : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        workspace = current_workspace(ctx)
        workspace_id = workspace_id_from_ctx(ctx)
        {
          "workspace_id" => JSON.parse(workspace_id.to_json),
          "workspace_action" => JSON.parse("open".to_json),
          "workspace_session_url" => JSON.parse("workspace://#{workspace_id}".to_json),
          "workspace" => JSON.parse(workspace.to_json),
        }
      end
    end

    private def docker_workspace_delete : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        workspace = current_workspace(ctx)
        workspace_id = workspace_id_from_ctx(ctx)
        {
          "workspace_id" => JSON.parse(workspace_id.to_json),
          "workspace_action" => JSON.parse("delete".to_json),
          "workspace_deleted" => JSON.parse(true.to_json),
          "workspace" => JSON.parse(workspace.to_json),
        }
      end
    end

    private def current_workspace(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::AnyHash
      ctx.input_data["workspace"]?.try(&.as_h?) || ({} of String => JSON::Any)
    end

    private def workspace_id_from_ctx(ctx : Cogni::Workflow::NodeContext) : String
      from_input = ctx.input_data["input"]?.try(&.as_h?).try(&.["workspace_id"]?).try(&.as_s?)
      from_state = ctx.state["workspace_id"]?.try(&.as_s?)
      from_input || from_state || "ws_unknown"
    end
  end
end
