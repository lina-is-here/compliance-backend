# frozen_string_literal: true

module Types
  # Definition of the BaseObject type in GraphQL
  class BaseObject < GraphQL::Types::Relay::BaseObject
    implements GraphQL::Relay::Node.interface
    connection_type_class Connections::BaseConnection

    add_field GraphQL::Types::Relay::NodeField
    add_field GraphQL::Types::Relay::NodesField

    class << self
      def model_class(new_model_class = nil)
        if new_model_class
          @model_class = new_model_class
        else
          @model_class ||= "::#{to_s.demodulize}".safe_constantize
        end
      end
    end

    protected

    def lookahead_includes(lookahead, object, selects_includes)
      selects_includes.each do |selects, includes|
        object = object.includes(includes) if lookahead.selects?(selects)
      end

      object
    end
  end
end
