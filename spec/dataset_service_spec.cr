require "./spec_helper"

describe Ocawe::Dataset::Service do
  it "creates and lists datasets" do
    service = Ocawe::Dataset::Service.new

    service.create_dataset("users", description: "User profiles")
    datasets = service.list_datasets

    datasets.size.should eq(1)
    datasets.first.id.should eq("users")
    datasets.first.description.should eq("User profiles")
  end

  it "registers DSL datasets without duplicating seed items on reload" do
    service = Ocawe::Dataset::Service.new

    seed = {"id" => json_any("seed-1"), "name" => json_any("Ada")} of String => JSON::Any

    service.register_from_dsl("profiles", source_file: "a.acd.cr", seed_items: [seed])
    service.reset_dsl_sources!
    service.register_from_dsl("profiles", source_file: "a.acd.cr", seed_items: [seed])

    items = service.list_items("profiles")
    items.size.should eq(1)
    items.first.id.should eq("seed-1")
  end

  it "validates items against dataset schema" do
    service = Ocawe::Dataset::Service.new

    service.create_dataset(
      "feedback",
      schema_source: "Schema::Types.object({\"rating\" => Schema::Types.of(Int32)})"
    )

    service.add_items("feedback", [
      {"rating" => json_any(5)} of String => JSON::Any,
    ])

    expect_raises(Exception, /validation failed/) do
      service.add_items("feedback", [
        {"rating" => json_any("bad")} of String => JSON::Any,
      ])
    end
  end

  it "updates and deletes items" do
    service = Ocawe::Dataset::Service.new
    service.create_dataset("events")

    created = service.add_items("events", [
      {"id" => json_any("evt-1"), "name" => json_any("launch")} of String => JSON::Any,
    ])

    created.first.id.should eq("evt-1")
    service.update_item("events", "evt-1", {"name" => json_any("release")} of String => JSON::Any)

    after_update = service.list_items("events")
    after_update.first.payload["name"].as_s.should eq("release")

    service.delete_item("events", "evt-1").should eq(true)
    service.list_items("events").size.should eq(0)
  end
end
