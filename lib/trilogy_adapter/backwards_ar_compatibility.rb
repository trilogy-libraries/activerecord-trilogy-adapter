# frozen_string_literal: true

# Patches to allow ActiveRecord 5.2, 6.0, 6.1, and 7.0 to work successfully
# with Trilogy.  The approach taken is to patch older code in
# ConnectionAdapters so that it behaves in the same kind of way as
# ActiveRecord 7.1.  This works without requiring any code changes to the
# ActiveRecord Trilogy Adapter itself.

require "socket"
module ::ActiveRecord
  # For ActiveRecord <= 5.2
  unless const_defined?("QueryAborted")
    class QueryAborted < StatementInvalid
    end
  end

  # For ActiveRecord <= 7.0
  unless const_defined?("ConnectionFailed")
    class ConnectionFailed < QueryAborted
    end
  end

  begin
    require "active_record/database_configurations"
    # For ActiveRecord 6.0
    unless DatabaseConfigurations.instance_methods.include?(:resolve)
      DatabaseConfigurations.class_exec do
        def resolve(config) # :nodoc:
          @resolver ||= ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(::ActiveRecord::Base.configurations)
          @resolver.resolve(config)
        end
      end
    end
  rescue LoadError
    # For ActiveRecord <= 5.2
    class DatabaseConfigurations < ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver
      def initialize(configurations = {}, *args)
        super(::ActiveRecord::Base.configurations)
      end
    end
  end

  require "active_record/connection_adapters/abstract_mysql_adapter"
  module ConnectionAdapters
    unless AbstractAdapter.private_instance_methods.include?(:with_raw_connection)
      AbstractAdapter.class_exec do
        # For ActiveRecord <= 5.2
        unless self.respond_to?(:build_read_query_regexp)
          DEFAULT_READ_QUERY = [:begin, :commit, :explain, :release, :rollback, :savepoint, :select, :with] # :nodoc:
          COMMENT_REGEX = %r{(?:--.*\n)|/\*(?:[^*]|\*[^/])*\*/}m

          def self.build_read_query_regexp(*parts) # :nodoc:
            parts += DEFAULT_READ_QUERY
            parts = parts.map { |part| /#{part}/i }
            /\A(?:[(\s]|#{COMMENT_REGEX})*#{Regexp.union(*parts)}/
          end
        end

        # For ActiveRecord <= 6.1
        unless ::ActiveRecord::ConnectionAdapters::AbstractAdapter::Version.instance_methods.include?(:full_version_string)
          class ::ActiveRecord::ConnectionAdapters::AbstractAdapter::Version
            attr_reader :full_version_string

            alias _original_initialize initialize
            def initialize(version_string, full_version_string = nil)
              _original_initialize(version_string)
              @full_version_string = full_version_string
            end
          end
        end

      private

        # For ActiveRecord <= 7.0
        def with_raw_connection(allow_retry: false, uses_transaction: true)
          @lock.synchronize do
            @raw_connection = nil unless instance_variable_defined?(:@raw_connection)
            verify! unless @verified # || (@raw_connection.server_status & 1).positive?
            materialize_transactions if uses_transaction
            begin
              yield @raw_connection
            rescue StandardError => exception
              @verified = false unless exception.is_a?(Deadlocked) || exception.is_a?(LockWaitTimeout)
              # raise translate_exception_class(exception, nil, nil)
              # raise translate_exception(exception, message: exception.message, sql: nil, binds: nil)
              raise exception
            end
          end
        end
      end
    end

    if AbstractAdapter.instance_method(:execute).parameters.length < 3
      require "active_record/connection_adapters/trilogy_adapter"
      TrilogyAdapter.class_exec do
        # For ActiveRecord <= 7.0
        def initialize(*args, **kwargs)
          if kwargs.present?
            args << kwargs.dup
            kwargs.clear
          end
          # Turn  .new(config)  into  .new(nil, nil, nil, config)
          3.times { args.unshift nil } if args.length < 4
          super
          if @connection
            @verified = true
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

        alias _original_active? active?
        def active?
          return false if connection&.closed?

          _original_active?
        end

        def reconnect!
          @lock.synchronize do
            disconnect!
            connect
          rescue => original_exception
            @verified = false
            raise translate_exception_class(original_exception, nil, nil)
          end
        end
        alias :reset! :reconnect!

        # For ActiveRecord <= 6.1
        if AbstractMysqlAdapter.instance_method(:execute).parameters.length < 3
          # Adds an #execute specific to the TrilogyAdapter that allows
          # (but disregards) +async+ and other keyword parameters.
          alias raw_execute execute
          def execute(sql, name = nil, **kwargs)
            @raw_connection = nil unless instance_variable_defined?(:@raw_connection)
            # 16384 tests the bit flag for SERVER_SESSION_STATE_CHANGED, which gets set when the
            # last statement executed has caused a change in the server's state.
            # Was:  (!@verified && !active?)
            reconnect if @raw_connection.nil? || (!@verified && (@raw_connection&.server_status & 16384).zero?)
            raw_execute(sql, name)
          rescue => original_exception
            @verified = false unless original_exception.is_a?(Deadlocked) || original_exception.is_a?(LockWaitTimeout)
            raise
          end
        end

      private

        # For ActiveRecord <= 7.0
        alias _original_connection_equals connection=
        def connection=(*args)
          @verified = false unless (@connection = _original_connection_equals(*args))
          @connection
        end

        def full_version
          get_full_version
        end

        if ActiveRecord.respond_to?(:default_timezone)
          # For ActiveRecord 7.0
          def default_timezone
            ActiveRecord.default_timezone
          end
        else
          # For ActiveRecord <= 6.1
          def default_timezone
            ActiveRecord::Base.default_timezone
          end
        end

        # For ActiveRecord <= 5.2
        if ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter.instance_method(:translate_exception).parameters.length < 4
          alias _original_translate_exception translate_exception
          def translate_exception(exception, *args)
            _original_translate_exception(exception, message: args.first, sql: nil, binds: nil)
          end
        end
      end
    end

    if const_defined?("PoolConfig")
      # ActiveRecord <= 6.1
      if PoolConfig.instance_method(:initialize).parameters.length < 4
        class PoolConfig
          alias _original_initialize initialize
          def initialize(connection_class, db_config, *args)
            _original_initialize(connection_class, db_config)
          end
        end
      end
    else
      # For ActiveRecord <= 5.2
      class PoolConfig < ConnectionSpecification
        def initialize(connection_class, db_config, *args)
          super("primary", db_config, nil)
        end
      end
    end

    # For ActiveRecord <= 5.2
    unless SchemaCache.instance_methods.include?(:database_version)
      SchemaCache.class_exec do
        def database_version # :nodoc:
          @database_version ||= connection.get_database_version
        end

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

    # For ActiveRecord <= 5.2
    unless AbstractMysqlAdapter.instance_methods.include?(:get_database_version)
      TrilogyAdapter.class_exec do
        def get_database_version # :nodoc:
          ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::Version.new(
            get_full_version.match(/^(?:5\.5\.5-)?(\d+\.\d+\.\d+)/)[1]
          )
        end
      end
    end

    class AbstractMysqlAdapter
      # For ActiveRecord <= 5.2
      unless instance_methods.include?(:database_version)
        def database_version # :nodoc:
          schema_cache.database_version
        end
      end

      # For ActiveRecord <= 5.1
      if instance_methods.include?(:new_column)
        class_exec do
          def new_column(*args, **kwargs) #:nodoc:
            MySQL::Column.new(*args, **kwargs)
          end
        end
      end
    end

    require "active_record/connection_adapters/abstract/schema_definitions"
    class IndexDefinition
      # For ActiveRecord <= 6.0
      unless instance_methods.include?(:column_options)
        alias _original_initialize initialize
        def initialize(*args, **options)
          options.merge!(args.pop) if args.length > 4
          _original_initialize(*args, **options)
        end
      end
    end

    require "active_record/connection_adapters/abstract/transaction"
    class Transaction # :nodoc:
      # For For ActiveRecord <= 5.2
      unless instance_methods.include?(:isolation_level)
        attr_reader :isolation_level

        alias _original_initialize initialize
        def initialize(connection, *args, isolation: nil, joinable: true, run_commit_callbacks: false)
          _original_initialize(connection, args.first, run_commit_callbacks: run_commit_callbacks)
          @isolation_level = isolation
          @joinable = joinable
        end
      end
    end
  end
end
