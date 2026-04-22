require "./spec_helper"
require "file_utils"

describe Cogni::Dataset::Service do
  it "creates and lists datasets" do
    service = Cogni::Dataset::Service.new

    service.create_dataset("users", description: "User profiles")
    datasets = service.list_datasets

    datasets.size.should eq(1)
    datasets.first.id.should eq("users")
    datasets.first.description.should eq("User profiles")
  end

  it "registers DSL datasets without duplicating seed items on reload" do
    service = Cogni::Dataset::Service.new

    seed = {"id" => json_any("seed-1"), "name" => json_any("Ada")} of String => JSON::Any

    service.register_from_dsl("profiles", source_file: "a.acd.cr", seed_items: [seed])
    service.reset_dsl_sources!
    service.register_from_dsl("profiles", source_file: "a.acd.cr", seed_items: [seed])

    items = service.list_items("profiles")
    items.size.should eq(1)
    items.first.id.should eq("seed-1")
  end

  it "validates items against dataset schema" do
    service = Cogni::Dataset::Service.new

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
    service = Cogni::Dataset::Service.new
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

  it "imports dataset items from json and stores schema description metadata" do
    dir = "/tmp/cogni_dataset_json_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(dir)
    path = File.join(dir, "tickets.json")
    File.write(path, %([{"id":"t1","title":"Outage","priority":1},{"id":"t2","title":"Billing","priority":2}]))

    service = Cogni::Dataset::Service.new
    dataset = service.create_dataset(
      "tickets",
      description: "Imported tickets",
      schema_description: "Support ticket payload with numeric priority",
      schema_source: "Schema::Types.object({\"title\" => Schema::Types.of(String), \"priority\" => Schema::Types.of(Int32)})",
      source_path: path,
      source_format: "json",
    )

    dataset.schema_description.should eq("Support ticket payload with numeric priority")
    dataset.source_path.should eq(path)
    dataset.source_format.should eq("json")
    service.list_items("tickets").size.should eq(2)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "imports dataset items from csv and infers scalar values" do
    dir = "/tmp/cogni_dataset_csv_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(dir)
    path = File.join(dir, "scores.csv")
    File.write(path, "id,name,score,active\nu1,Ada,10,true\nu2,Linus,7,false\n")

    service = Cogni::Dataset::Service.new
    dataset = service.register_from_dsl(
      "scores",
      source_file: File.join(dir, "scores.acd.cr"),
      source_path: path,
      source_format: "csv",
      schema_source: "Schema::Types.object({\"name\" => Schema::Types.of(String), \"score\" => Schema::Types.of(Int32), \"active\" => Schema::Types.of(Bool)})",
      base_dir: dir,
    )

    dataset.source_format.should eq("csv")
    items = service.list_items("scores")
    items.size.should eq(2)
    items.first.payload["score"].as_i.should eq(10)
    items.first.payload["active"].raw.should eq(true)
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
