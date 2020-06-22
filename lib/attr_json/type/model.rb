module AttrJson
  module Type
    # An ActiveModel::Type representing a particular AttrJson::Model
    # class, supporting casting, serialization, and deserialization from/to
    # JSON-able serializable hashes.
    #
    # You create one with AttrJson::Model::Type.new(attr_json_model_class),
    # but normally that's only done in AttrJson::Model.to_type, there isn't
    # an anticipated need to create from any other place.
    #
    # ## ActiveRecord `serialize`
    #
    # This class also provides #dump and #load methods, so it can be used
    # with ActiveRecord `serialize` feature, to map a single AttrJson::Model
    # to a json/jsonb column.
    # https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html
    #
    # class ValueModel
    #   include AttrJson::Model
    #   attr_json :some_string, :string
    # end
    #
    # class SomeModel < ApplicationRecord
    #   serialize :some_json_column, ValueModel.to_type
    # end
    class Model < ::ActiveModel::Type::Value
      class BadCast < ArgumentError ; end

      attr_accessor :model
      def initialize(model)
        #TODO type check, it really better be a AttrJson::Model. maybe?
        @model = model
      end

      def type
        model.to_param.underscore.to_sym
      end

      def cast(v)
        if v.nil?
          # important to stay nil instead of empty object, because they
          # are different things.
          v
        elsif v.kind_of? model
          v
        elsif v.respond_to?(:to_hash)
          # to_hash is actually the 'implicit' conversion, it really is a hash
          # even though it isn't is_a?(Hash), try to_hash first before to_h,
          # the explicit conversion.
          model.new_from_serializable(v.to_hash)
        elsif v.respond_to?(:to_h)
          # TODO Maybe we ought not to do this on #to_h?
          model.new_from_serializable(v.to_h)
        elsif model.attr_json_config.bad_cast == :as_nil
          # This was originally default behavior, to be like existing ActiveRecord
          # which kind of silently does this for non-castable basic values. That
          # ended up being confusing in the basic case, so now we raise by default,
          # but this is still configurable.
          nil
        else
          raise BadCast.new("Can not cast from #{v.inspect} to #{self.type}")
        end
      end

      def serialize(v)
        if v.nil?
          nil
        elsif v.kind_of?(model)
          v.serializable_hash
        else
          cast(v).serializable_hash
        end
      end

      def deserialize(v)
        cast(v)
      end

      # these guys are definitely mutable, so we need this.
      def changed_in_place?(raw_old_value, new_value)
        serialize(new_value) != raw_old_value
      end

      # This is used only by our own keypath-chaining query stuff.
      def value_for_contains_query(key_path_arr, value)
        first_key, rest_keys = key_path_arr.first, key_path_arr[1..-1]
        attr_def = model.attr_json_registry.fetch(first_key)
        {
          attr_def.store_key => if rest_keys.present?
            attr_def.type.value_for_contains_query(rest_keys, value)
          else
            attr_def.serialize(attr_def.cast value)
          end
        }
      end

      # Dump and load methods to support ActiveRecord Serialization
      # too. https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html
      def dump(value)
        serialize(value)
      end

      # Dump and load methods to support ActiveRecord Serialization
      # too. https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html
      def load(value)
        deserialize(value)
      end
    end
  end
end
