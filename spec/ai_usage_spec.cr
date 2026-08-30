require "./spec_helper"

describe OcaweCore::AI::TokenUsage do
  it "maps standard OpenAI usage fields" do
    usage = OcaweCore::AI::TokenUsage.from_payload(JSON.parse(%({"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}))).not_nil!

    usage.prompt_tokens.should eq(12)
    usage.completion_tokens.should eq(8)
    usage.total_tokens.should eq(20)
  end

  it "maps Open Responses input and output fields" do
    usage = OcaweCore::AI::TokenUsage.from_payload(JSON.parse(%({"usage":{"input_tokens":12,"output_tokens":8}}))).not_nil!

    usage.prompt_tokens.should eq(12)
    usage.completion_tokens.should eq(8)
    usage.total_tokens.should eq(20)
  end

  it "keeps missing provider usage unknown" do
    OcaweCore::AI::TokenUsage.from_payload(JSON.parse(%({"id":"response"}))).should be_nil
  end
end
