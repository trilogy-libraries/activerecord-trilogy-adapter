# frozen_string_literal: true

# Patches to allow ActiveRecord 6.1 and 7.0 to work successfully
# with Trilogy.  The approach taken is to patch older code in
# ConnectionAdapters so that it behaves in the same kind of way as
# ActiveRecord 7.1.  This works without requiring any code changes to the
# ActiveRecord Trilogy Adapter itself.

require "socket"
# :nodoc:
module ::ActiveRecord
  # For ActiveRecord <= 7.0
  unless const_defined?("ConnectionFailed")
    class ConnectionFailed < QueryAborted
    end
  end

  # For ActiveRecord <= 6.1
  unless const_defined?("DatabaseConnectionError")
    class DatabaseConnectionError < ConnectionNotEstablished # :nodoc:
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
  end

  # For ActiveRecord <= 6.1
  unless NoDatabaseError.respond_to?(:db_error)
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

  require "active_record/connection_adapters/abstract_mysql_adapter"
  module ConnectionAdapters # :nodoc:
    unless AbstractAdapter.private_instance_methods.include?(:with_raw_connection)
      AbstractAdapter.class_exec do
        # For ActiveRecord <= 6.1
        unless self::Version.instance_methods.include?(:full_version_string)
          module ::ActiveRecord
            module ConnectionAdapters
              class AbstractAdapter::Version # :nodoc:
                attr_reader :full_version_string

                alias _original_initialize initialize
                def initialize(version_string, full_version_string = nil)
                  _original_initialize(version_string)
                  @full_version_string = full_version_string
                end
              end
            end
          end
        end

        private

        # For ActiveRecord <= 7.0
        def with_raw_connection(uses_transaction: true, **_kwargs)
          @lock.synchronize do
            @raw_connection = @connection || nil unless instance_variable_defined?(:@raw_connection)
            unless @verified
              verify!
              @verified = true
            end
            materialize_transactions if uses_transaction
            begin
              yield @raw_connection
            rescue StandardError => e
              @verified = false unless e.is_a?(Deadlocked) || e.is_a?(LockWaitTimeout) ||
                                       ( # Timed out while in a transaction?
                                         (@raw_connection.server_status & 1).positive? &&
                                         (e.is_a?(Trilogy::ClientError) || e.is_a?(Errno::ETIMEDOUT))
                                       )
              raise
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

        alias_method :_original_active?, :active?
        def active?
          return false if connection&.closed?

          _original_active?
        end

        def reconnect!
          @lock.synchronize do
            disconnect!
            connect
          rescue StandardError => original_exception
            @verified = false
            raise translate_exception_class(original_exception, nil, nil)
          end
        end
        alias_method :reset!, :reconnect!

        def exec_rollback_db_transaction
          # 16384 tests the bit flag for SERVER_SESSION_STATE_CHANGED, which gets set when the
          # last statement executed has caused a change in the server's state.
          if active? || (@raw_connection.server_status & 16_384).positive?
            super
          else
            @verified = false
          end
        end

        # For ActiveRecord <= 6.1
        if AbstractMysqlAdapter.instance_method(:execute).parameters.length < 3
          # Adds an #execute specific to the TrilogyAdapter that allows
          # (but disregards) +async+ and other keyword parameters.
          alias_method :raw_execute, :execute
          def execute(sql, name = nil, **_kwargs)
            @raw_connection = nil unless instance_variable_defined?(:@raw_connection)
            reconnect if @raw_connection.nil? || (!@verified && (@raw_connection.server_status & 16_384).zero?)
            if default_timezone == :local
              @raw_connection.query_flags |= ::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            else
              @raw_connection.query_flags &= ~::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            end
            raw_execute(sql, name)
          rescue StandardError => e
            return if e.is_a?(Deadlocked)

            @verified = false unless e.is_a?(LockWaitTimeout) ||
                                     ((@raw_connection.server_status & 1).positive? &&
                                      e.cause.is_a?(Errno::ETIMEDOUT))
            raise
          end
        else # For ActiveRecord 7.0
          def execute(sql, name = nil, **kwargs)
            sql = transform_query(sql)
            check_if_write_query(sql)
            super
          end
        end

        # For ActiveRecord <= 7.0
        alias_method :_original_connection_equals, :connection=
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
      end
    end

    # ActiveRecord <= 6.1
    if const_defined?("PoolConfig") && PoolConfig.instance_method(:initialize).parameters.length < 4
      class PoolConfig # :nodoc:
        alias _original_initialize initialize
        def initialize(connection_class, db_config, *_args)
          _original_initialize(connection_class, db_config)
        end
      end
    end
  end
end

# A do-nothing placeholder allowing AR 7.0 to function when the Trilogy driver is not patched with PR#15:
# https://github.com/github/trilogy/pull/15
class ::Trilogy
  unless const_defined?('ClientError')
    class ClientError < ::StandardError
    end
  end
end
