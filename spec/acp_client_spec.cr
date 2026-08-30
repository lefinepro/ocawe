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
        client.session_models.not_nil!.as_a.first["id"].as_s.should eq("gpt-5.4")
        client.set_model("gpt-5.4").as_h["modelId"].as_s.should eq("gpt-5.4")
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

    it "selects allow-once for ACP permission requests" do
      mock_script = File.join(__DIR__, "support", "mock_acp_agent.cr")
      next unless File.file?(mock_script)

      client = ACP::Client.new("crystal", ["run", mock_script], {"MOCK_ACP_REQUEST_PERMISSION" => "1"})
      begin
        client.start
        client.create_session(Dir.current)
        client.prompt("Use a tool").stopReason.should eq("end_turn")
      ensure
        client.close
      end
    end

    it "drains every queued response chunk without a fixed limit" do
      mock_script = File.join(__DIR__, "support", "mock_acp_agent.cr")
      next unless File.file?(mock_script)

      client = ACP::Client.new("crystal", ["run", mock_script], {"MOCK_ACP_CHUNKS" => "many"})
      begin
        client.start
        client.create_session(Dir.current)
        client.prompt("Stream a response")
        chunks = client.drain_updates.compact_map(&.update.content.try(&.text))
        chunks.size.should eq(12)
        chunks.join.should eq((1..12).map { |index| "chunk-#{index}" }.join)
      ensure
        client.close
      end
    end
  end
end
