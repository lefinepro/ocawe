require "./spec_helper"

describe Ocawe::Workflows::DSL::CrystalDSL do
  it "compiles and validates supported schema dsl expressions" do
    validator = Ocawe::Workflows::DSL::CrystalDSL.compile(
      "Schema::Types.object({\"task\" => Schema::Types.of(String), \"tags\" => Schema::Types.optional(Schema::Types.array(Schema::Types.of(String)))})",
      "schema-spec"
    )

    valid_payload = JSON.parse({
      "task" => "write tests",
      "tags" => ["crystal", "dsl"],
    }.to_json)
    validator.validate(valid_payload)

    expect_raises(Ocawe::Workflows::DSL::ValidationError) do
      invalid_payload = JSON.parse({"tags" => ["missing task"]}.to_json)
      validator.validate(invalid_payload)
    end
  end

  it "rejects unsupported methods in schema dsl" do
    expect_raises(Ocawe::Workflows::DSL::CrystalDSL::ParseError) do
      Ocawe::Workflows::DSL::CrystalDSL.compile("Schema::Types.unknown()", "schema-invalid")
    end
  end

  it "accepts output schema that is a superset of input schema" do
    input_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
      "Schema::Types.object({\"task\" => Schema::Types.of(String), \"tags\" => Schema::Types.optional(Schema::Types.array(Schema::Types.of(String)))}, strict: true)",
      "input-schema"
    )
    output_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
      "Schema::Types.object({\"task\" => Schema::Types.of(String), \"tags\" => Schema::Types.optional(Schema::Types.array(Schema::Types.of(String))), \"answer\" => Schema::Types.optional(Schema::Types.of(String))}, strict: false)",
      "output-schema"
    )

    Ocawe::Workflows::DSL::Compatibility.ensure_output_superset!(input_schema, output_schema)
  end

  it "rejects output schema that drops required input field" do
    input_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
      "Schema::Types.object({\"task\" => Schema::Types.of(String), \"answer\" => Schema::Types.of(String)}, strict: true)",
      "input-schema"
    )
    output_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
      "Schema::Types.object({\"task\" => Schema::Types.of(String)}, strict: true)",
      "output-schema"
    )

    expect_raises(Ocawe::Workflows::DSL::ValidationError, /answer/) do
      Ocawe::Workflows::DSL::Compatibility.ensure_output_superset!(input_schema, output_schema)
    end
  end
end
