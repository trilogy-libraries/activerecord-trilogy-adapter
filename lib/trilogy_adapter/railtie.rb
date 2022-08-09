# frozen_string_literal: true

if defined?(Rails)
  require "rails/railtie"

  module TrilogyAdapter
    class Railtie < ::Rails::Railtie
      ActiveSupport.on_load(:active_record) do
        require "trilogy_adapter/connection"
        ActiveRecord::Base.public_send :extend, TrilogyAdapter::Connection
      end
    end
  end
end

if defined?(Rails::DBConsole)
  require "trilogy_adapter/rails/dbconsole"
  Rails::DBConsole.prepend(TrilogyAdapter::Rails::DBConsole)
end
