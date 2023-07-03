# frozen_string_literal: true

require "trilogy"
require "active_record/connection_adapters/abstract_mysql_adapter"

require "active_record/tasks/trilogy_database_tasks"
require "trilogy_adapter/lost_connection_exception_translator"

module ActiveRecord
  # ActiveRecord <= 6.1 support
  if ActiveRecord.version < ::Gem::Version.new('7.0.a')
    class DatabaseConnectionError < ConnectionNotEstablished
      def initialize(message = nil)
        super(message || "Database connection error")
      end

      class << self
        def hostname_error(hostname)
          DatabaseConnectionError.new(<<~MSG)
            There is an issue connecting with your hostname: #{hostname}.\n
            Please check your database configuration and ensure there is a valid connection to your database.
          MSG
        end

        def username_error(username)
          DatabaseConnectionError.new(<<~MSG)
            There is an issue connecting to your database with your username/password, username: #{username}.\n
            Please check your database configuration to ensure the username/password are valid.
          MSG
        end
      end
    end

    NoDatabaseError.class_exec do
      def self.db_error(db_name)
        NoDatabaseError.new(<<~MSG)
          We could not find your database: #{db_name}. Available database configurations can be found in config/database.yml file.

          To resolve this error:

          - Did you create the database for this app, or delete it? You may need to create your database.
          - Has the database name changed? Check your database.yml config has the correct database name.

          To create your database, run:\n\n        bin/rails db:create
        MSG
      end
    end
  end

  if ActiveRecord.version < ::Gem::Version.new('6.1.a') # ActiveRecord <= 6.0 support
    require "active_record/database_configurations"
    DatabaseConfigurations.class_exec do
      def resolve(config) # :nodoc:
        @resolver ||= ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(::ActiveRecord::Base.configurations)
        @resolver.resolve(config)
      end
    end
  end

  module ConnectionAdapters
    class TrilogyAdapter < ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter
      module DatabaseStatements
        READ_QUERY = ActiveRecord::ConnectionAdapters::AbstractAdapter.build_read_query_regexp(
          :desc, :describe, :set, :show, :use
        ) # :nodoc:
        private_constant :READ_QUERY

        HIGH_PRECISION_CURRENT_TIMESTAMP = Arel.sql("CURRENT_TIMESTAMP(6)").freeze # :nodoc:
        private_constant :HIGH_PRECISION_CURRENT_TIMESTAMP

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

        def high_precision_current_timestamp
          HIGH_PRECISION_CURRENT_TIMESTAMP
        end

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
            if error.message.include?("TRILOGY_DNS_ERROR")
              ActiveRecord::DatabaseConnectionError.hostname_error(config[:host])
            else
              ActiveRecord::ConnectionNotEstablished.new(error.message)
            end
          end
        end
      end

      def initialize(connection, logger, connection_options, config)
        super
        # Ensure that we're treating prepared_statements in the same way that Rails 7.1 does
        @prepared_statements = self.class.type_cast_config_to_boolean(
          @config.fetch(:prepared_statements) { default_prepared_statements }
        )
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
        with_trilogy_connection(allow_retry: true, uses_transaction: false) do |conn|
          conn.escape(string)
        end
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

      if ActiveRecord.version < ::Gem::Version.new('7.0.a') # ActiveRecord <= 6.1 support
        def raw_execute(sql, name, uses_transaction: true, **_kwargs)
          # Same as mark_transaction_written_if_write(sql)
          transaction = current_transaction
          if transaction.respond_to?(:written) && transaction.open?
            transaction.written ||= write_query?(sql)
          end

          log(sql, name) do
            with_trilogy_connection(uses_transaction: uses_transaction) do |conn|
              sync_timezone_changes(conn)
              conn.query(sql)
            end
          end
        end

        def execute(sql, name = nil, **_kwargs)
          raw_execute(sql, name, **_kwargs)
        end
      else # ActiveRecord 7.0 support
        def raw_execute(sql, name, uses_transaction: true, async: false, allow_retry: false)
          mark_transaction_written_if_write(sql)
          log(sql, name, async: async) do
            with_trilogy_connection(uses_transaction: uses_transaction, allow_retry: allow_retry) do |conn|
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
      end

      def active?
        return false if connection&.closed?

        connection&.ping || false
      rescue ::Trilogy::Error
        false
      end

      alias reset! reconnect!

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
        attr_accessor :connection

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

        def execute_batch(statements, name = nil)
          statements = statements.map { |sql| transform_query(sql) } if respond_to?(:transform_query)
          combine_multi_statements(statements).each do |statement|
            with_trilogy_connection do |conn|
              raw_execute(statement, name)
              conn.next_result while conn.more_results_exist?
            end
          end
        end

        def multi_statements_enabled?
          !!@config[:multi_statement]
        end

        def with_multi_statements
          if multi_statements_enabled?
            return yield
          end

          with_trilogy_connection do |conn|
            conn.set_server_option(Trilogy::SET_SERVER_MULTI_STATEMENTS_ON)

            yield
          ensure
            conn.set_server_option(Trilogy::SET_SERVER_MULTI_STATEMENTS_OFF)
          end
        end

        def combine_multi_statements(total_sql)
          total_sql.each_with_object([]) do |sql, total_sql_chunks|
            previous_packet = total_sql_chunks.last
            if max_allowed_packet_reached?(sql, previous_packet)
              total_sql_chunks << +sql
            else
              previous_packet << ";\n"
              previous_packet << sql
            end
          end
        end

        def max_allowed_packet_reached?(current_packet, previous_packet)
          if current_packet.bytesize > max_allowed_packet
            raise ActiveRecordError,
              "Fixtures set is too large #{current_packet.bytesize}. Consider increasing the max_allowed_packet variable."
          elsif previous_packet.nil?
            true
          else
            (current_packet.bytesize + previous_packet.bytesize + 2) > max_allowed_packet
          end
        end

        def max_allowed_packet
          @max_allowed_packet ||= show_variable("max_allowed_packet")
        end

        def full_version
          schema_cache.database_version.full_version_string
        end

        def get_full_version
          with_trilogy_connection(allow_retry: true, uses_transaction: false) do |conn|
            conn.server_info[:version]
          end
        end

        if ActiveRecord.version < ::Gem::Version.new('7.0.a') # For ActiveRecord <= 6.1
          def default_timezone
            ActiveRecord::Base.default_timezone
          end
        else # For ActiveRecord 7.0
          def default_timezone
            ActiveRecord.default_timezone
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

        if ActiveRecord.version < ::Gem::Version.new('6.1.a') # For ActiveRecord <= 6.0
          def prepared_statements?
            @prepared_statements && !prepared_statements_disabled_cache.include?(object_id)
          end
        end
    end

    if ActiveRecord.version < ::Gem::Version.new('6.1.a') # For ActiveRecord <= 6.0
      class PoolConfig < ConnectionSpecification
        def initialize(connection_class, db_config, *args)
          super("primary", db_config, "#{db_config[:adapter]}_connection")
        end
      end

      SchemaCache.class_exec do
        def self.load_from(filename)
          return unless File.file?(filename)

          read(filename) do |file|
            if filename.include?(".dump")
              Marshal.load(file)
            else
              if YAML.respond_to?(:unsafe_load)
                YAML.unsafe_load(file)
              else
                YAML.load(file)
              end
            end
          end
        end

        def self.read(filename, &block)
          if File.extname(filename) == ".gz"
            Zlib::GzipReader.open(filename) { |gz|
              yield gz.read
            }
          else
            yield File.read(filename)
          end
        end
        private_class_method :read
      end
    end
  end
end
