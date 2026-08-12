Ocawe::RegistryApi.register_function("pass_input") do |ctx|
  value = ctx.input_data["input"]?.try(&.as_s?) || ""
  {
    "last_response" => JSON.parse(value.to_json),
    "status"        => JSON.parse("ok".to_json),
  }
end
