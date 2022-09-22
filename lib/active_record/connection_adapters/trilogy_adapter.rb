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

        def execute(sql, name = nil, async: false)
          sql = transform_query(sql)
          check_if_write_query(sql)

          raw_execute(sql, name, async: async)
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
      ER_CONN_HOST_ERROR = 2003
      ER_UNKNOWN_HOST_ERROR = 2005

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
        def database_driver=(database_driver = ::Trilogy)
          @database_driver = database_driver
        end

        def database_driver
          @database_driver ||= ::Trilogy
        end

        def new_client(config)
          config[:ssl_mode] = parse_ssl_mode(config[:ssl_mode]) if config[:ssl_mode]
          database_driver.new(config)
        rescue Trilogy::DatabaseError => error
          raise translate_connect_error(config, error)
        end

        def parse_ssl_mode(mode)
          return unless mode

          # return mode if it's already a Trilogy::SSL_MODE
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
          when ER_CONN_HOST_ERROR, ER_UNKNOWN_HOST_ERROR
            ActiveRecord::DatabaseConnectionError.hostname_error(config[:host])
          else
            ActiveRecord::ConnectionNotEstablished.new(error.message)
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
        connection&.ping || false
      rescue ::Trilogy::Error
        false
      end

      alias reset! reconnect!

      def disconnect!
        unless connection.nil?
          connection.close
          self.connection = nil
        end
      end

      def discard!
        self.connection = nil
      end

      def raw_execute(sql, name, async: false, allow_retry: false, uses_transaction: true)
        mark_transaction_written_if_write(sql)

        log(sql, name, async: async) do
          with_raw_connection(allow_retry: allow_retry, uses_transaction: uses_transaction) do |conn|
            # Sync any changes since connection last established.
            if default_timezone == :local
              conn.query_flags |= ::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            else
              conn.query_flags &= ~::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            end

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
          @raw_connection = conn
        end

        def connect
          self.connection = self.class.new_client(@config)
        end

        def reconnect
          connection&.close
          connect
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
    end
  end
end
