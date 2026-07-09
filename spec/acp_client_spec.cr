require "./spec_helper"
require "json"

describe "ACP::Client" do
  describe "initialization" do
    it "starts with initialize request" do
      mock_script = File.join(__DIR__, "support", "mock_acp_agent.cr")
      next unless File.file?(mock_script)

      client = ACP::Client.new("crystal", ["run", mock_script])
      begin
        result = client.start

        result.agentInfo.should_not be_nil
        result.agentInfo.not_nil!.name.should eq("mock-acp")
        result.agentInfo.not_nil!.version.should eq("1.0.0")
        result.agentCapabilities.should_not be_nil
        result.agentCapabilities.not_nil!.loadSession.should eq(false)
      ensure
        client.close
      end
    end
  end

  describe "session management" do
    it "creates a session" do
      mock_script = File.join(__DIR__, "support", "mock_acp_agent.cr")
      next unless File.file?(mock_script)

      client = ACP::Client.new("crystal", ["run", mock_script])
      begin
        client.start
        session_id = client.create_session(Dir.current)
        session_id.should be_a(String)
        session_id.includes?("sess_mock").should eq(true)
        client.session_id.should eq(session_id)
      ensure
        client.close
      end
    end
  end

  describe "prompt/response" do
    it "sends prompt and receives response" do
      mock_script = File.join(__DIR__, "support", "mock_acp_agent.cr")
      next unless File.file?(mock_script)

      client = ACP::Client.new("crystal", ["run", mock_script])
      begin
        client.start
        client.create_session(Dir.current)

        result = client.prompt("Hello, ACP!")
        result.stopReason.should eq("end_turn")
      ensure
        client.close
      end
    end
  end
end
