# frozen_string_literal: true

# Patches to allow ActiveRecord 6.1 and 7.0 to work successfully
# with Trilogy.  The approach taken is to patch older code in
# ConnectionAdapters so that it behaves in the same kind of way as
# ActiveRecord 7.1.  This works without requiring any code changes to the
# ActiveRecord Trilogy Adapter itself.

require "socket"
module ::ActiveRecord
  # For ActiveRecord <= 7.0
  unless const_defined?("ConnectionFailed")
    class ConnectionFailed < QueryAborted
    end
  end

  require "active_record/connection_adapters/abstract_mysql_adapter"
  module ConnectionAdapters
    unless AbstractAdapter.private_instance_methods.include?(:with_raw_connection)
      AbstractAdapter.class_exec do
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
      end
    end

    # ActiveRecord <= 6.1
    if const_defined?("PoolConfig") && PoolConfig.instance_method(:initialize).parameters.length < 4
      class PoolConfig
        alias _original_initialize initialize
        def initialize(connection_class, db_config, *args)
          _original_initialize(connection_class, db_config)
        end
      end
    end
  end
end
