# frozen_string_literal: true

require "trilogy"
require "active_record/connection_adapters/trilogy_adapter"

module TrilogyAdapter
  # Necessary for enhancing ActiveRecord to recognize the Trilogy adapter. Example:
  #
  #   ActiveRecord::Base.public_send :extend, TrilogyAdapter::Connection
  #
  # This will allow downstream applications to use the Trilogy adapter. Example:
  #
  #   ActiveRecord::Base.establish_connection adapter: "trilogy",
  #                                           host: "localhost",
  #                                           database: "demo_development"
  module Connection
    def trilogy_adapter_class
      ActiveRecord::ConnectionAdapters::TrilogyAdapter
    end

    def trilogy_connection(config)
      configuration = config.dup

      # Set FOUND_ROWS capability on the connection so UPDATE queries returns number of rows
      # matched rather than number of rows updated.
      configuration[:found_rows] = true

      options = [
        configuration[:host],
        configuration[:port],
        configuration[:database],
        configuration[:username],
        configuration[:password],
        configuration[:socket],
        0
      ]

      trilogy_adapter_class.new nil, logger, options, configuration
    end
  end
end
