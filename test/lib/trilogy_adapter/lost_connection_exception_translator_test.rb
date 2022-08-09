# frozen_string_literal: true

require "test_helper"

class TrilogyAdapter::LostConnectionExceptionTranslatorTest < TestCase
  test "#translate returns appropriate TrilogyAdapter error for Trilogy exceptions" do
    translator = TrilogyAdapter::LostConnectionExceptionTranslator.new(
      Trilogy::DatabaseError.new,
      "ER_SERVER_SHUTDOWN 1053",
      1053
    )

    assert_kind_of(TrilogyAdapter::Errors::ServerShutdown, translator.translate)
  end

  test "#translate returns nil for Trilogy exceptions when the error code is not given" do
    translator = TrilogyAdapter::LostConnectionExceptionTranslator.new(
      Trilogy::DatabaseError.new,
      "ER_SERVER_SHUTDOWN 1053",
      nil
    )

    assert_nil translator.translate
  end

  test "#translate returns appropriate TrilogyAdapter error for Ruby exceptions" do
    translator = TrilogyAdapter::LostConnectionExceptionTranslator.new(
      SocketError.new,
      "Failed to open TCP connection",
      nil
    )

    assert_kind_of(TrilogyAdapter::Errors::SocketError, translator.translate)
  end

  test "#translate returns appropriate TrilogyAdapter error for lost connection Trilogy exceptions" do
    translator = TrilogyAdapter::LostConnectionExceptionTranslator.new(
      Trilogy::Error.new,
      "TRILOGY_UNEXPECTED_PACKET",
      nil
    )

    assert_kind_of(TrilogyAdapter::Errors::UnexpectedPacket, translator.translate)
  end

  test "#translate returns nil for non-lost connection exceptions" do
    translator = TrilogyAdapter::LostConnectionExceptionTranslator.new(
      Trilogy::Error.new,
      "Something bad happened but it wasn't a lost connection so...",
      nil
    )

    assert_nil translator.translate
  end
end
