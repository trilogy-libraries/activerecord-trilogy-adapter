# frozen_string_literal: true

module TrilogyAdapter
  module Rails
    module DBConsole
      class AdapterAdapter < SimpleDelegator
        def adapter
          "mysql"
        end
      end

      def db_config
        if super.adapter == "trilogy"
          AdapterAdapter.new(super)
        else
          super
        end
      end
    end
  end
end
