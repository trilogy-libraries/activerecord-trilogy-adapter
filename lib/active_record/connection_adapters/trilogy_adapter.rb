# frozen_string_literal: true

require "trilogy"
require "active_record/connection_adapters/abstract_mysql_adapter"

require "active_record/tasks/trilogy_database_tasks"
require "active_record/connection_adapters/trilogy/database_statements"

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
      ER_BAD_DB_ERROR = 1049
      ER_DBACCESS_DENIED_ERROR = 1044
      ER_ACCESS_DENIED_ERROR = 1045
      ER_SERVER_SHUTDOWN = 1053

      ADAPTER_NAME = "Trilogy"

      include Trilogy::DatabaseStatements

      SSL_MODES = {
        SSL_MODE_DISABLED: ::Trilogy::SSL_DISABLED,
        SSL_MODE_PREFERRED: ::Trilogy::SSL_PREFERRED_NOVERIFY,
        SSL_MODE_REQUIRED: ::Trilogy::SSL_REQUIRED_NOVERIFY,
        SSL_MODE_VERIFY_CA: ::Trilogy::SSL_VERIFY_CA,
        SSL_MODE_VERIFY_IDENTITY: ::Trilogy::SSL_VERIFY_IDENTITY
      }.freeze

      class << self
        def new_client(config)
          config[:ssl_mode] = parse_ssl_mode(config[:ssl_mode]) if config[:ssl_mode]
          ::Trilogy.new(config)
        rescue ::Trilogy::Error => error
          raise translate_connect_error(config, error)
        end

        def parse_ssl_mode(mode)
          return mode if mode.is_a? Integer

          m = mode.to_s.upcase
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

        def dbconsole(config, options = {})
          mysql_config = if ActiveRecord.version < ::Gem::Version.new('6.1.a')
                           config.config
                         else
                           config.configuration_hash
                         end

          args = {
            host: "--host",
            port: "--port",
            socket: "--socket",
            username: "--user",
            encoding: "--default-character-set",
            sslca: "--ssl-ca",
            sslcert: "--ssl-cert",
            sslcapath: "--ssl-capath",
            sslcipher: "--ssl-cipher",
            sslkey: "--ssl-key",
            ssl_mode: "--ssl-mode"
          }.filter_map { |opt, arg| "#{arg}=#{mysql_config[opt]}" if mysql_config[opt] }

          if mysql_config[:password] && options[:include_password]
            args << "--password=#{mysql_config[:password]}"
          elsif mysql_config[:password] && !mysql_config[:password].to_s.empty?
            args << "-p"
          end

          args << mysql_config[:database]

          find_cmd_and_exec(["mysql", "mysql5"], *args)
        end

        private
          def initialize_type_map(m)
            super if ActiveRecord.version >= ::Gem::Version.new('7.0.a')

            m.register_type(%r(char)i) do |sql_type|
              limit = extract_limit(sql_type)
              Type.lookup(:string, adapter: :trilogy, limit: limit)
            end

            m.register_type %r(^enum)i, Type.lookup(:string, adapter: :trilogy)
            m.register_type %r(^set)i,  Type.lookup(:string, adapter: :trilogy)
          end
      end

      def initialize(connection, logger, connection_options, config)
        config = config.dup

        # Trilogy ignores `socket` if `host` is set. We want the opposite to allow
        # configuring UNIX domain sockets via `DATABASE_URL`.
        config.delete(:host) if config[:socket]

        super
        # Ensure that we're treating prepared_statements in the same way that Rails 7.1 does
        @prepared_statements = self.class.type_cast_config_to_boolean(
          @config.fetch(:prepared_statements) { default_prepared_statements }
        )
      end

      TYPE_MAP = Type::TypeMap.new.tap { |m| initialize_type_map(m) }

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
        with_trilogy_connection(allow_retry: true, materialize_transactions: false) do |conn|
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
        end
      end

      def with_trilogy_connection(materialize_transactions: true, **_kwargs)
        @lock.synchronize do
          verify!
          self.materialize_transactions if materialize_transactions
          yield connection
        end
      end

      def connected?
        !connection.nil?
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
        super
        unless connection.nil?
          connection.discard!
          self.connection = nil
        end
      end

      def error_number(exception)
        exception.error_code if exception.respond_to?(:error_code)
      end

      def self.find_cmd_and_exec(commands, *args) # :doc:
        commands = Array(commands)

        dirs_on_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
        unless (ext = RbConfig::CONFIG["EXEEXT"]).empty?
          commands = commands.map { |cmd| "#{cmd}#{ext}" }
        end

        full_path_command = nil
        found = commands.detect do |cmd|
          dirs_on_path.detect do |path|
            full_path_command = File.join(path, cmd)
            begin
              stat = File.stat(full_path_command)
            rescue SystemCallError
            else
              stat.file? && stat.executable?
            end
          end
        end

        if found
          exec full_path_command, *args
        else
          abort("Couldn't find database client: #{commands.join(', ')}. Check your $PATH and try again.")
        end
      end

      private
        def text_type?(type)
          TYPE_MAP.lookup(type).is_a?(Type::String) || TYPE_MAP.lookup(type).is_a?(Type::Text)
        end

        def each_hash(result)
          return to_enum(:each_hash, result) unless block_given?

          keys = result.columns.map(&:to_sym)
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

        attr_accessor :connection

        def connect
          self.connection = self.class.new_client(@config)
          configure_connection
        end

        def reconnect
          connection&.close
          self.connection = nil
          connect
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
          with_trilogy_connection(allow_retry: true, materialize_transactions: false) do |conn|
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

        def default_prepared_statements
          false
        end

        if ActiveRecord.version < ::Gem::Version.new('6.1.a') # For ActiveRecord <= 6.0
          def prepared_statements?
            @prepared_statements && !prepared_statements_disabled_cache.include?(object_id)
          end
        end

        def default_insert_value(column)
          super unless column.auto_increment?
        end

        # https://mariadb.com/kb/en/analyze-statement/
        def analyze_without_explain?
          mariadb? && database_version >= "10.1.0"
        end

        ActiveRecord::Type.register(:immutable_string, adapter: :trilogy) do |_, **args|
          Type::ImmutableString.new(true: "1", false: "0", **args)
        end

        ActiveRecord::Type.register(:string, adapter: :trilogy) do |_, **args|
          Type::String.new(true: "1", false: "0", **args)
        end

        ActiveRecord::Type.register(:unsigned_integer, Type::UnsignedInteger, adapter: :trilogy)
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

    ActiveSupport.run_load_hooks(:active_record_trilogyadapter, TrilogyAdapter)
  end
end
