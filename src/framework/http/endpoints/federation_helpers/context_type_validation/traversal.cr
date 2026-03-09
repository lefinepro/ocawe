module ACD
  module Kemal
    class App
      private def validate_contextual_json_node(
        node : JSON::Any,
        path : String,
        inherited_contexts : Set(String),
        require_type : Bool = false
      ) : Array(String)
        errors = [] of String
        if hash = node.as_h?
          contexts = effective_contexts(hash, inherited_contexts)
          types = type_names_for(hash)
          if require_type && types.empty?
            errors << "#{path}.type is required for #{context_label(contexts)} object"
          end
          if !types.empty? && !contexts.empty?
            types.each do |type_name|
              next if type_allowed_for_contexts?(type_name, contexts)
              errors << "#{path}.type=#{type_name} is not allowed by #{context_label(contexts)}"
            end
          end
          errors.concat(validate_known_type_shape(hash, path, types))
          hash.each do |key, value|
            next if key == "@context"
            errors.concat(
              validate_contextual_child(
                value,
                path: "#{path}.#{key}",
                inherited_contexts: contexts,
                require_type: nested_typed_object_required?(key, value),
              )
            )
          end
        elsif array = node.as_a?
          array.each_with_index do |entry, index|
            errors.concat(
              validate_contextual_json_node(
                entry,
                path: "#{path}[#{index}]",
                inherited_contexts: inherited_contexts,
              )
            )
          end
        end
        errors
      end

      private def validate_contextual_child(
        value : JSON::Any,
        path : String,
        inherited_contexts : Set(String),
        require_type : Bool
      ) : Array(String)
        return [] of String unless value.as_h? || value.as_a?
        validate_contextual_json_node(
          JSON.parse(value.to_json),
          path: path,
          inherited_contexts: inherited_contexts,
          require_type: require_type,
        )
      end
    end
  end
end
