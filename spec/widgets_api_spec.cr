require "./spec_helper"

describe Api::Widgets do
  it "builds an ActivityStreams object block with marketplace units and grid layout" do
    article = Aptok.article(
      "https://example.test/widgets/weather/article",
      name: "Weather in Berlin",
      summary: "Sunny, 21 C",
      content: {"location" => "Berlin", "temperature" => 21, "unit" => "C"}.to_json,
      media_type: "application/json"
    )

    block = Api::Widgets.block(
      "https://example.test/widgets/weather/block",
      article,
      col: 2,
      row: 3,
      width: 4,
      height: 2,
      unit: "weather"
    )

    block["@context"].as_a.first.as_s.should eq(Aptok::ACTIVITYSTREAMS_CONTEXT)
    block["@context"].as_a[1].as_h["vf"].as_s.should eq(Aptok::VALUEFLOWS_CONTEXT)
    block["type"].as_a.map(&.as_s).should eq(["Object", "Block"])
    block["object"].as_h["type"].as_s.should eq("Article")
    block["position"].as_h["col"].as_i.should eq(2)
    block["position"].as_h["row"].as_i.should eq(3)
    block["width"].as_i.should eq(4)
    block["height"].as_i.should eq(2)
    block.has_key?("resourceConformsTo").should be_false
    block["resourceQuantity"].as_h["hasUnit"].as_s.should eq("weather")
    block["resourceQuantity"].as_h["hasNumericalValue"].as_s.should eq("1")
  end

  it "builds ordered pages of widget blocks" do
    article = Aptok.article("https://example.test/widgets/article", name: "Any widget")
    block = Api::Widgets.block("https://example.test/widgets/block", article, col: 1, row: 1, width: 3, height: 1)

    page = Api::Widgets.ordered_page(
      "https://example.test/widgets?page=1",
      "https://example.test/widgets",
      [block]
    )

    page["@context"].as_a.first.as_s.should eq(Aptok::ACTIVITYSTREAMS_CONTEXT)
    page["type"].as_s.should eq("OrderedCollectionPage")
    page["partOf"].as_s.should eq("https://example.test/widgets")
    page["orderedItems"].as_a.first.as_h["id"].as_s.should eq("https://example.test/widgets/block")
  end

  it "rejects invalid grid layout values" do
    article = Aptok.article("https://example.test/widgets/article", name: "Any widget")

    expect_raises(ArgumentError, "widget block width must be >= 1") do
      Api::Widgets.block("https://example.test/widgets/block", article, col: 1, row: 1, width: 0, height: 1)
    end
  end
end
