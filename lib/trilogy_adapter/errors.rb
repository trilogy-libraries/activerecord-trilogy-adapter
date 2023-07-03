# frozen_string_literal: true

if ActiveRecord.version < ::Gem::Version.new('6.1.a') # ActiveRecord <= 6.0 support
  module ::ActiveRecord
    class QueryAborted < ::ActiveRecord::StatementInvalid
    end
    class AdapterTimeout < ::ActiveRecord::QueryAborted
    end
  end
end

module TrilogyAdapter
  module Errors
    # ServerShutdown will be raised when the database server was shutdown.
    class ServerShutdown < ::ActiveRecord::QueryAborted
    end

    # ServerLost will be raised when the database connection was lost.
    class ServerLost < ::ActiveRecord::QueryAborted
    end

    # ServerGone will be raised when the database connection is gone.
    class ServerGone < ::ActiveRecord::QueryAborted
    end

    # BrokenPipe will be raised when a system process connection fails.
    class BrokenPipe < ::ActiveRecord::QueryAborted
    end

    # SocketError will be raised when Ruby encounters a network error.
    class SocketError < ::ActiveRecord::QueryAborted
    end

    # ConnectionResetByPeer will be raised when a network connection is closed
    # outside the sytstem process.
    class ConnectionResetByPeer < ::ActiveRecord::QueryAborted
    end

    # ClosedConnection will be raised when the Trilogy encounters a closed
    # connection.
    class ClosedConnection < ::ActiveRecord::QueryAborted
    end

    # InvalidSequenceId will be raised when Trilogy ecounters an invalid sequence
    # id.
    class InvalidSequenceId < ::ActiveRecord::QueryAborted
    end

    # UnexpectedPacket will be raised when Trilogy ecounters an unexpected
    # response packet.
    class UnexpectedPacket < ::ActiveRecord::QueryAborted
    end
  end
end
