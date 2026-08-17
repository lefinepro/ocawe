Ocawe::Command.register("set_value", ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
  {
    "function_status" => JSON.parse("ok".to_json),
    "input_value" => ctx.input_data["value"]? || JSON.parse("missing".to_json),
  }
end)
