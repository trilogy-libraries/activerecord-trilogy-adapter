# frozen_string_literal: true

module TrilogyAdapter
  module BackwardsCompatibility
    def initialize(connection, logger, connection_options, config)
      super
      if @connection
        @raw_connection = @connection
      end
      # Ensure that we're treating prepared_statements in the same way that Rails 7.1 does
      @prepared_statements = self.class.type_cast_config_to_boolean(
        @config.fetch(:prepared_statements) { default_prepared_statements }
      )
    end

    def connect!
      verify!
      self
    end

    def reconnect!
      @lock.synchronize do
        disconnect!
        connect
      rescue StandardError => original_exception
        raise translate_exception_class(original_exception, nil, nil)
      end
    end

    def with_trilogy_connection(uses_transaction: true, **_kwargs)
      @lock.synchronize do
        @raw_connection = @connection || nil unless instance_variable_defined?(:@raw_connection)
        verify!
        materialize_transactions if uses_transaction
        yield @raw_connection
      end
    end

    def execute(sql, name = nil, **kwargs)
      sql = transform_query(sql)
      check_if_write_query(sql)
      super
    end

    def full_version
      get_full_version
    end

    def default_timezone
      ActiveRecord.default_timezone
    end
  end
end
