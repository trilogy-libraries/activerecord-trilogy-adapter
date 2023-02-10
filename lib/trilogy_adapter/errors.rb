# frozen_string_literal: true

module TrilogyAdapter
  module Errors
    connection_failed_base = if ::ActiveRecord.version < ::Gem::Version.new('7.1.a')
                               ::ActiveRecord::QueryAborted
                             else
                               ::ActiveRecord::ConnectionFailed
                             end

    # ServerShutdown will be raised when the database server was shutdown.
    class ServerShutdown < connection_failed_base
    end

    # ServerLost will be raised when the database connection was lost.
    class ServerLost < connection_failed_base
    end

    # ServerGone will be raised when the database connection is gone.
    class ServerGone < connection_failed_base
    end

    # BrokenPipe will be raised when a system process connection fails.
    class BrokenPipe < connection_failed_base
    end

    # SocketError will be raised when Ruby encounters a network error.
    class SocketError < connection_failed_base
    end

    # ConnectionResetByPeer will be raised when a network connection is closed
    # outside the sytstem process.
    class ConnectionResetByPeer < connection_failed_base
    end

    # ClosedConnection will be raised when the Trilogy encounters a closed
    # connection.
    class ClosedConnection < connection_failed_base
    end

    # InvalidSequenceId will be raised when Trilogy ecounters an invalid sequence
    # id.
    class InvalidSequenceId < connection_failed_base
    end

    # UnexpectedPacket will be raised when Trilogy ecounters an unexpected
    # response packet.
    class UnexpectedPacket < connection_failed_base
    end
  end
end
