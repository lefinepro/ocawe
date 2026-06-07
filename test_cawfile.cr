require "rcl"
require "json"
require "./src/framework/discovery/cawfile_loader"

test_dir = "/tmp/test-cawfile-example"
Dir.mkdir_p(test_dir)

File.write(File.join(test_dir, "Cawfile"), <<-RCL)
workflow "solver-example" do
  version = "1.0.0"
  description = "Example workflow bundle"
  packages = ["git", "docker", "nodejs"]

  key "OPENAI_API_KEY" do
    required = true
    description = "OpenAI API key"
    provider = "openai"
  end

  agent "code-reviewer" do
    prompt = "Review code for issues"
    model = "qwen3-coder"
    description = "Code reviewer"
  end

  step "agent-check" do
    model = "qwen3-coder"
  end
end
RCL

bundle = ACD::Discovery::CawfileLoader.load(test_dir, "solver-example")
puts "Loaded: #{bundle.not_nil!.id}"
puts "Version: #{bundle.not_nil!.version}"
puts "Packages: #{bundle.not_nil!.packages.inspect}"
puts "Keys: #{bundle.not_nil!.keys.map { |k| "#{k.name} required=#{k.required}" }.inspect}"
puts "Agents: #{bundle.not_nil!.agents.map { |a| "#{a.id} model=#{a.model}" }.inspect}"
puts "Steps: #{bundle.not_nil!.workflow_steps.map { |s| "#{s.type}-#{s.id} params=#{s.params.keys}" }.inspect}"
