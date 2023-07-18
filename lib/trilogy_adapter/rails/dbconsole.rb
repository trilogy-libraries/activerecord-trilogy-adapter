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

module Rails
  class DBConsole
    # require "rails/commands/dbconsole/dbconsole_command"
    if ActiveRecord.version < ::Gem::Version.new('6.1.a')
      alias _brick_start start
      def start
        ENV["RAILS_ENV"] ||= @options[:environment] || environment

        if config["adapter"] == "trilogy"
          begin
            ::ActiveRecord::ConnectionAdapters::TrilogyAdapter.dbconsole(config, @options)
          rescue NotImplementedError
            abort "Unknown command-line client for #{db_config.database}."
          end
        else
          _brick_start
        end
      end
    end
  end
end
