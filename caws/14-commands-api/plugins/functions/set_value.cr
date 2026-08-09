Ocawe::RegistryApi.register_function("set_value") do |ctx|
  {
    "function_status" => JSON.parse("ok".to_json),
    "input_value" => ctx.input_data["value"]? || JSON.parse("missing".to_json),
  }
end
