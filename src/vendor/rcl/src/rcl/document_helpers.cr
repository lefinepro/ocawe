require "set"

module RCL
  module DocumentHelpers
    private def unique_child_blocks(block : BlockNode) : Array(BlockNode)
      seen = Set(UInt64).new
      out = [] of BlockNode
      block.blocks.each_value do |child|
        oid = child.object_id
        next if seen.includes?(oid)
        seen << oid
        out << child
      end
      block.named_blocks.each do |child|
        oid = child.object_id
        next if seen.includes?(oid)
        seen << oid
        out << child
      end
      out
    end

    private def insert_key_path!(target : Hash(String, RCL::Value), key : String, value : RCL::Value)
      parts = key.split('.')
      if parts.size == 1
        raise "Duplicate key '#{key}'" if target.has_key?(key)
        target[key] = value
        return
      end
      head = parts[0]
      existing = target[head]?
      if existing && !existing.is_a?(Hash(String, RCL::Value))
        raise "Key conflict at '#{head}'"
      end
      branch = existing.as?(Hash(String, RCL::Value)) || ({} of String => RCL::Value)
      insert_key_path!(branch, parts[1..].join("."), value)
      target[head] = branch
    end

    private def named_base(name : String) : String
      name == "region" ? "regions" : name
    end
  end
end
