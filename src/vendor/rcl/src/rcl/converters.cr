require "./document"

module RCL
  module Converters
    def self.to_yaml(value : RCL::Value) : String
      emit_yaml(value, 0)
    end

    def self.to_toml(value : RCL::Value) : String
      root = value.is_a?(Hash(String, RCL::Value)) ? value : {"root" => value} of String => RCL::Value
      lines = [] of String
      emit_toml_table(root, nil, lines)
      lines.join("\n")
    end

    def self.to_hcl(value : RCL::Value) : String
      root = value.is_a?(Hash(String, RCL::Value)) ? value : {"root" => value} of String => RCL::Value
      emit_hcl(root, 0)
    end

    private def self.emit_yaml(value : RCL::Value, indent : Int32) : String
      case value
      when Hash(String, RCL::Value)
        lines = [] of String
        value.keys.sort.each do |key|
          item = value[key]
          if item.is_a?(Hash(String, RCL::Value)) || item.is_a?(Array(RCL::Value))
            lines << "#{"  " * indent}#{key}:"
            lines << emit_yaml(item, indent + 1)
          else
            lines << "#{"  " * indent}#{key}: #{emit_scalar(item)}"
          end
        end
        lines.join("\n")
      when Array(RCL::Value)
        lines = [] of String
        value.each do |item|
          if item.is_a?(Hash(String, RCL::Value)) || item.is_a?(Array(RCL::Value))
            lines << "#{"  " * indent}-"
            lines << emit_yaml(item, indent + 1)
          else
            lines << "#{"  " * indent}- #{emit_scalar(item)}"
          end
        end
        lines.join("\n")
      else
        emit_scalar(value)
      end
    end

    private def self.emit_toml_table(hash : Hash(String, RCL::Value), prefix : String?, lines : Array(String))
      scalar_keys = hash.keys.select { |k| !hash[k].is_a?(Hash(String, RCL::Value)) }.sort
      scalar_keys.each do |key|
        lines << "#{key} = #{emit_scalar(hash[key])}"
      end

      table_keys = hash.keys.select { |k| hash[k].is_a?(Hash(String, RCL::Value)) }.sort
      table_keys.each do |key|
        section = prefix ? "#{prefix}.#{key}" : key
        lines << "" unless lines.empty?
        lines << "[#{section}]"
        emit_toml_table(hash[key].as(Hash(String, RCL::Value)), section, lines)
      end
    end

    private def self.emit_hcl(value : RCL::Value, indent : Int32) : String
      case value
      when Hash(String, RCL::Value)
        lines = [] of String
        value.keys.sort.each do |key|
          item = value[key]
          if item.is_a?(Hash(String, RCL::Value))
            lines << "#{"  " * indent}#{key} {"
            lines << emit_hcl(item, indent + 1)
            lines << "#{"  " * indent}}"
          else
            lines << "#{"  " * indent}#{key} = #{emit_scalar(item)}"
          end
        end
        lines.join("\n")
      else
        emit_scalar(value)
      end
    end

    private def self.emit_scalar(value : RCL::Value) : String
      case value
      when String
        %("#{escape_string(value)}")
      when Int32, Int64, Float64
        value.to_s
      when Bool
        value ? "true" : "false"
      when Array(RCL::Value)
        "[#{value.map { |v| emit_scalar(v) }.join(", ")}]"
      when Hash(String, RCL::Value)
        "{}"
      end
    end

    private def self.escape_string(value : String) : String
      value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n").gsub("\t", "\\t")
    end
  end
end
