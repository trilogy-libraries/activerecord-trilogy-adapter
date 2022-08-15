# frozen_string_literal: true

module TrilogyAdapter
  module Errors
    error_superclass = if ActiveRecord.version <= Gem::Version.new("7.0.0")
                   ActiveRecord::StatementInvalid
                 else
                   ActiveRecord::ConnectionFailed
                 end

    # ServerShutdown will be raised when the database server was shutdown.
    class ServerShutdown < error_superclass
    end

    # ServerLost will be raised when the database connection was lost.
    class ServerLost < error_superclass
    end

    # ServerGone will be raised when the database connection is gone.
    class ServerGone < error_superclass
    end

    # BrokenPipe will be raised when a system process connection fails.
    class BrokenPipe < error_superclass
    end

    # SocketError will be raised when Ruby encounters a network error.
    class SocketError < error_superclass
    end

    # ConnectionResetByPeer will be raised when a network connection is closed
    # outside the sytstem process.
    class ConnectionResetByPeer < error_superclass
    end

    # ClosedConnection will be raised when the Trilogy encounters a closed
    # connection.
    class ClosedConnection < error_superclass
    end

    # InvalidSequenceId will be raised when Trilogy ecounters an invalid sequence
    # id.
    class InvalidSequenceId < error_superclass
    end

    # UnexpectedPacket will be raised when Trilogy ecounters an unexpected
    # response packet.
    class UnexpectedPacket < error_superclass
    end
  end
end
