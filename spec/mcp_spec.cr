require "./spec_helper"

describe "mcp support" do
  it "parses mcp references" do
    server, name = Cogni::MCP.parse_mcp_ref("mcp:remote:echo")
    server.should eq("remote")
    name.should eq("echo")
  end

  it "exposes mcp config defaults" do
    settings = Cogni::Config::Settings.default
    settings.mcp.dynamic_store_path.should eq(".meta/mcp_servers.json")
    settings.mcp.http_server.path.should eq("/mcp")
  end
end
