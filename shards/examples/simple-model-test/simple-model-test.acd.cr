workflow "simple-model-test" do
  @[Resources(model: "cliproxyapi/qwen3-coder-plus")]

  agent "simple-model-agent"
end
