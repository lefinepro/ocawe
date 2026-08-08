require "./spec_helper"
require "../src/framework/translation/compatibility"

describe Ocawe::Translation do
  it "detects formats from paths and request shapes" do
    Ocawe::Translation.detect("/v1/messages", "{}").should eq(Ocawe::Translation::Format::AnthropicMessages)
    Ocawe::Translation.detect("/v1/responses", "{}").should eq(Ocawe::Translation::Format::OpenResponses)
    Ocawe::Translation.detect("/v1/unknown", {"messages" => [] of String}.to_json).should eq(Ocawe::Translation::Format::ChatCompletions)
  end

  it "normalizes Anthropic system and content blocks to chat messages" do
    body = JSON.parse({
      "model"    => "claude-test",
      "system"   => "Answer briefly.",
      "messages" => [
        {"role" => "user", "content" => [{"type" => "text", "text" => "Hello"}]},
      ],
      "max_tokens" => 32,
    }.to_json).as_h

    normalized = Ocawe::Translation.anthropic_request_as_chat(body.to_json)
    messages = JSON.parse(normalized)["messages"].as_a

    messages.size.should eq(2)
    messages[0]["role"].as_s.should eq("system")
    messages[0]["content"].as_s.should eq("Answer briefly.")
    messages[1]["role"].as_s.should eq("user")
    messages[1]["content"].as_s.should eq("Hello")
  end

  it "renders a chat completion in Anthropic response shape" do
    completion = JSON.parse({
      "id"      => "chatcmpl_test",
      "model"   => "test-model",
      "choices" => [{
        "message"       => {"role" => "assistant", "content" => "Hi"},
        "finish_reason" => "stop",
      }],
      "usage" => {"prompt_tokens" => 3, "completion_tokens" => 1},
    }.to_json).as_h

    response = JSON.parse(Ocawe::Translation.chat_response_as_anthropic(
      completion.to_json,
      {"model" => "request-model"}.to_json,
    ))

    response["id"].as_s.should eq("chatcmpl_test")
    response["type"].as_s.should eq("message")
    response["content"].as_a[0]["text"].as_s.should eq("Hi")
    response["usage"]["input_tokens"].as_i.should eq(3)
    response["usage"]["output_tokens"].as_i.should eq(1)
  end

  it "uses the request model when a completion omits one" do
    completion = JSON.parse({
      "choices" => [{"message" => {"role" => "assistant", "content" => "Hi"}}],
    }.to_json).as_h
    request = JSON.parse({"model" => "request-model"}.to_json).as_h

    response = JSON.parse(Ocawe::Translation.chat_response_as_anthropic(completion.to_json, request.to_json))
    response["model"].as_s.should eq("request-model")
  end
end
