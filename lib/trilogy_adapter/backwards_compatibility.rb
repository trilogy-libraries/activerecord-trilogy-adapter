# frozen_string_literal: true

module TrilogyAdapter
  module BackwardsCompatibility
    def initialize(connection, logger, connection_options, config)
      super
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
        verify!
        materialize_transactions if uses_transaction
        yield connection
      end
    end

    def raw_execute(sql, name, async: false, allow_retry: false, uses_transaction: true)
      mark_transaction_written_if_write(sql)

      log(sql, name, async: async) do
        with_trilogy_connection(allow_retry: allow_retry, uses_transaction: uses_transaction) do |conn|
          sync_timezone_changes(conn)
          conn.query(sql)
        end
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
