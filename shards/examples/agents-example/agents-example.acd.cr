workflow "agents-example" do
  @[Resources(model: "cliproxyapi/qwen3-coder-plus")]
  agent "simple-agent"
end
