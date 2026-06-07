# docker-git foundation example built on Ocawe primitives.

workflow "docker-git" do
  @[Workspace(
    provider: "docker",
    runtime: "docker",
    repo: "https://github.com/ProverCoderAI/docker-git",
    profile: "foundation",
    secrets: {github_token: "secret://github/token"},
    scope: "workflow"
  )]
  docker_workspace_create

  @[Workspace(branch: "main", mode: "clone", scope: "node")]
  docker_workspace_clone

  @[Workspace(mode: "open", mcp_playwright: true, scope: "node")]
  docker_workspace_open

  @[Workspace(mode: "delete", scope: "node")]
  docker_workspace_delete
end
