require "./spec_helper"

private class EmptyProvider
  include OcaweCore::AI::Provider

  def generate_text(request : OcaweCore::AI::TextGenerationRequest) : OcaweCore::AI::TextGenerationResponse
    OcaweCore::AI::TextGenerationResponse.new("test", request.model, "  ")
  end
end

private class ToolCallOnlyProvider
  include OcaweCore::AI::Provider

  def generate_text(request : OcaweCore::AI::TextGenerationRequest) : OcaweCore::AI::TextGenerationResponse
    tool_calls = [JSON.parse({"id" => "call-1", "type" => "function"}.to_json)]
    OcaweCore::AI::TextGenerationResponse.new("test", request.model, "", tool_calls)
  end
end

describe OcaweCore::AI::Client do
  it "fails empty text responses without tool calls" do
    client = OcaweCore::AI::Client.new({"test" => EmptyProvider.new.as(OcaweCore::AI::Provider)})

    expect_raises(Exception, /empty response/) do
      client.generate_text("test/model", "prompt")
    end
  end

  it "allows empty text responses with tool calls" do
    client = OcaweCore::AI::Client.new({"test" => ToolCallOnlyProvider.new.as(OcaweCore::AI::Provider)})

    response = client.generate_text("test/model", "prompt")
    response.tool_calls.try(&.size).should eq(1)
  end
end
