require "./spec_helper"

describe "agent prompt contract injection" do
  it "applies ForgeFed merge contract when api/activity are present in state" do
    result = Ocawe::AgentFunctionHandlers.test_apply_agent_prompt_contracts_with_state(
      "Implement ticket changes",
      {"input" => json_any({"content" => "task"})} of String => JSON::Any,
      {
        "api"      => json_str("federation"),
        "activity" => json_str("merge"),
      } of String => JSON::Any
    )

    result.includes?("FORGEFED MERGE OUTPUT CONTRACT (MANDATORY)").should eq(true)
  end

  it "prepends ForgeFed merge instructions for federation merge runs" do
    result = Ocawe::AgentFunctionHandlers.test_apply_agent_prompt_contracts(
      "Implement ticket changes",
      {
        "api"      => json_str("federation"),
        "activity" => json_str("merge"),
      } of String => JSON::Any
    )

    result.includes?("FORGEFED MERGE OUTPUT CONTRACT (MANDATORY)").should eq(true)
    result.includes?("TASK:\nFILE OUTPUT CONTRACT (MANDATORY)").should eq(true)
    result.includes?("Implement ticket changes").should eq(true)
  end

  it "does not modify prompt outside federation merge runs" do
    result = Ocawe::AgentFunctionHandlers.test_apply_forgefed_merge_prompt_contract(
      "Plain task",
      {
        "api"      => json_str("classic"),
        "activity" => json_str("ticket"),
      } of String => JSON::Any
    )

    result.should eq("Plain task")
  end
end
