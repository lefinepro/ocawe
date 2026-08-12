Ocawe::RegistryApi.register_function("normalize_text") do |ctx|
  raw = ctx.input_data["input"]?.try(&.as_s?) || ""
  normalized = raw.split.join(" ")
  {
    "text"   => JSON.parse(normalized.to_json),
    "status" => JSON.parse("ok".to_json),
  }
end
