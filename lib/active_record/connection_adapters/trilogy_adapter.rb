# frozen_string_literal: true

require "trilogy"
require "active_record/connection_adapters/abstract_mysql_adapter"

require "active_record/tasks/trilogy_database_tasks"
require "trilogy_adapter/lost_connection_exception_translator"

module ActiveRecord
  module ConnectionAdapters
    class TrilogyAdapter < ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter
      module DatabaseStatements
        READ_QUERY = ActiveRecord::ConnectionAdapters::AbstractAdapter.build_read_query_regexp(
          :desc, :describe, :set, :show, :use
        ) # :nodoc:
        private_constant :READ_QUERY

        def write_query?(sql) # :nodoc:
          !READ_QUERY.match?(sql)
        rescue ArgumentError # Invalid encoding
          !READ_QUERY.match?(sql.b)
        end

        def explain(arel, binds = [])
          sql     = "EXPLAIN #{to_sql(arel, binds)}"
          start   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result  = exec_query(sql, "EXPLAIN", binds)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

          MySQL::ExplainPrettyPrinter.new.pp(result, elapsed)
        end

        def exec_query(sql, name = "SQL", binds = [], prepare: false, async: false)
          result = execute(sql, name, async: async)
          ActiveRecord::Result.new(result.fields, result.to_a)
        end

        alias exec_without_stmt exec_query

        def exec_insert(sql, name, binds, pk = nil, sequence_name = nil)
          execute(to_sql(sql, binds), name)
        end

        def exec_delete(sql, name = nil, binds = [])
          result = execute(to_sql(sql, binds), name)
          result.affected_rows
        end

        alias :exec_update :exec_delete

        private
          def last_inserted_id(result)
            result.last_insert_id
          end
      end

      ER_BAD_DB_ERROR = 1049
      ER_ACCESS_DENIED_ERROR = 1045

      ADAPTER_NAME = "Trilogy"

      include DatabaseStatements

      SSL_MODES = {
        SSL_MODE_DISABLED: Trilogy::SSL_DISABLED,
        SSL_MODE_PREFERRED: Trilogy::SSL_PREFERRED_NOVERIFY,
        SSL_MODE_REQUIRED: Trilogy::SSL_REQUIRED_NOVERIFY,
        SSL_MODE_VERIFY_CA: Trilogy::SSL_VERIFY_CA,
        SSL_MODE_VERIFY_IDENTITY: Trilogy::SSL_VERIFY_IDENTITY
      }.freeze

      class << self
        def new_client(config)
          config[:ssl_mode] = parse_ssl_mode(config[:ssl_mode]) if config[:ssl_mode]
          ::Trilogy.new(config)
        rescue Trilogy::ConnectionError, Trilogy::ProtocolError => error
          raise translate_connect_error(config, error)
        end

        def parse_ssl_mode(mode)
          return mode if mode.is_a? Integer

          m = mode.to_s.upcase
          # enable Mysql2 client compatibility
          m = "SSL_MODE_#{m}" unless m.start_with? "SSL_MODE_"

          SSL_MODES.fetch(m.to_sym, mode)
        end

        def translate_connect_error(config, error)
          case error.error_code
          when ER_BAD_DB_ERROR
            ActiveRecord::NoDatabaseError.db_error(config[:database])
          when ER_ACCESS_DENIED_ERROR
            ActiveRecord::DatabaseConnectionError.username_error(config[:username])
          else
            if error.message.match?(/TRILOGY_DNS_ERROR/)
              ActiveRecord::DatabaseConnectionError.hostname_error(config[:host])
            else
              ActiveRecord::ConnectionNotEstablished.new(error.message)
            end
          end
        end
      end

      def supports_json?
        !mariadb? && database_version >= "5.7.8"
      end

      def supports_comments?
        true
      end

      def supports_comments_in_create?
        true
      end

      def supports_savepoints?
        true
      end

      def savepoint_errors_invalidate_transactions?
        true
      end

      def supports_lazy_transactions?
        true
      end

      def quote_string(string)
        with_raw_connection(allow_retry: true, uses_transaction: false) do |conn|
          conn.escape(string)
        end
      end

      def active?
        return false if connection&.closed?

        connection&.ping || false
      rescue ::Trilogy::Error
        false
      end

      def disconnect!
        super
        unless connection.nil?
          connection.close
          self.connection = nil
        end
      end

      def discard!
        self.connection = nil
      end

      # ActiveRecord 7.0 support
      if ActiveRecord.version < ::Gem::Version.new('7.1.a')
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

        def with_raw_connection(uses_transaction: true, **_kwargs)
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

      alias_method :reset!, :reconnect!

      def raw_execute(sql, name, async: false, allow_retry: false, uses_transaction: true)
        mark_transaction_written_if_write(sql)

        log(sql, name, async: async) do
          with_raw_connection(allow_retry: allow_retry, uses_transaction: uses_transaction) do |conn|
            sync_timezone_changes(conn)
            conn.query(sql)
          end
        end
      end

      def each_hash(result)
        return to_enum(:each_hash, result) unless block_given?

        keys = result.fields.map(&:to_sym)
        result.rows.each do |row|
          hash = {}
          idx = 0
          row.each do |value|
            hash[keys[idx]] = value
            idx += 1
          end
          yield hash
        end

        nil
      end

      def error_number(exception)
        exception.error_code if exception.respond_to?(:error_code)
      end

      private
        def connection
          @raw_connection
        end

        def connection=(conn)
          @connection = conn if ActiveRecord.version < ::Gem::Version.new('7.1.a')
          @raw_connection = conn
        end

        def connect
          self.connection = self.class.new_client(@config)
        end

        def reconnect
          connection&.close
          self.connection = nil
          connect
        end

        def sync_timezone_changes(conn)
          # Sync any changes since connection last established.
          if default_timezone == :local
            conn.query_flags |= ::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
          else
            conn.query_flags &= ~::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
          end
        end

        def full_version
          schema_cache.database_version.full_version_string
        end

        def get_full_version
          with_raw_connection(allow_retry: true, uses_transaction: false) do |conn|
            conn.server_info[:version]
          end
        end

        def translate_exception(exception, message:, sql:, binds:)
          error_code = exception.error_code if exception.respond_to?(:error_code)

          ::TrilogyAdapter::LostConnectionExceptionTranslator.
            new(exception, message, error_code).translate || super
        end

        def default_prepared_statements
          false
        end
    end
  end
end
