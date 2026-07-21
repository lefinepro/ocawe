require "aptok"

module Api
  module Widgets
    def self.quantity(unit : String, value : String | Int32 | Int64 | Float64 | Nil = nil) : Aptok::JsonMap
      Aptok.marketplace_quantity(unit, value.try(&.to_s))
    end

    def self.position(col : Int32, row : Int32) : Aptok::JsonMap
      {
        "col" => Aptok.json(col),
        "row" => Aptok.json(row),
      } of String => JSON::Any
    end

    def self.block(
      id : String,
      object : Aptok::JsonMap,
      col : Int32,
      row : Int32,
      width : Int32,
      height : Int32,
      name : String? = nil,
      summary : String? = nil,
      unit : String = "widget",
      resource_conforms_to : String? = nil
    ) : Aptok::JsonMap
      validate_grid!(col, row, width, height)
      properties = {
        "@context"           => Aptok.marketplace_context,
        "type"               => Aptok.json(["Object", "Block"]),
        "name"               => Aptok.json(name || object["name"]?.try(&.as_s?) || "Widget block"),
        "object"             => Aptok.json(object),
        "position"           => Aptok.json(position(col, row)),
        "width"              => Aptok.json(width),
        "height"             => Aptok.json(height),
        "resourceQuantity"   => Aptok.json(quantity(unit, "1")),
      } of String => JSON::Any
      properties["summary"] = Aptok.json(summary) if summary
      properties["resourceConformsTo"] = Aptok.json(resource_conforms_to) if resource_conforms_to
      Aptok.object("Object", id, properties)
    end

    private def self.validate_grid!(col : Int32, row : Int32, width : Int32, height : Int32) : Nil
      raise ArgumentError.new("widget block col must be >= 1") if col < 1
      raise ArgumentError.new("widget block row must be >= 1") if row < 1
      raise ArgumentError.new("widget block width must be >= 1") if width < 1
      raise ArgumentError.new("widget block height must be >= 1") if height < 1
    end

    def self.ordered_page(
      id : String,
      part_of : String,
      blocks : Array(Aptok::JsonMap),
      next_id : String? = nil,
      prev_id : String? = nil
    ) : Aptok::JsonMap
      page = Aptok.ordered_collection_page(id, part_of, blocks, next_id, prev_id)
      page["@context"] = Aptok.marketplace_context
      page
    end

    def self.ordered_collection(id : String, blocks : Array(Aptok::JsonMap)) : Aptok::JsonMap
      collection = Aptok.ordered_collection(id, blocks)
      collection["@context"] = Aptok.marketplace_context
      collection
    end
  end
end
