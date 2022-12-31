# frozen_string_literal: true

require "pry"
require "minitest/autorun"
require "minitest/focus"

require "activerecord-trilogy-adapter"
require "trilogy_adapter/connection"
ActiveRecord::Base.public_send :extend, TrilogyAdapter::Connection

if ActiveRecord.respond_to?(:async_query_executor)
  ActiveRecord.async_query_executor = :multi_thread_pool
elsif ActiveRecord::Base.respond_to?(:async_query_executor)
  ActiveRecord::Base.async_query_executor = :multi_thread_pool
end

ENV["DB_HOST"] ||= "localhost"
ENV["DB_PORT"] ||= "3306"

class TestCase < ActiveSupport::TestCase
  DATABASE = "trilogy_test"

  setup do
    @fixtures_path = Pathname.new(File.expand_path(__dir__)).join "support", "fixtures"
  end

  def assert_raises_with_message(exception, message, &block)
    block.call
  rescue exception => error
    assert_match message, error.message
  else
    fail %(Expected #{exception} with message "#{message}" but nothing failed.)
  end

  # Create a temporary subscription to verify notification is sent.
  # Optionally verify the notification payload includes expected types.
  def assert_notification(notification, expected_payload = {}, &block)
    notification_sent = false

    subscription = lambda do |*args|
      notification_sent = true
      event = ActiveSupport::Notifications::Event.new(*args)

      expected_payload.each do |key, value|
        assert(
          value === event.payload[key],
          "Expected notification payload[:#{key}] to match #{value.inspect}, but got #{event.payload[key].inspect}."
        )
      end
    end

    ActiveSupport::Notifications.subscribed(subscription, notification) do
      block.call if block_given?
    end

    assert notification_sent, "#{notification} notification was not sent"
  end

  # Create a temporary subscription to verify notification was not sent.
  def assert_no_notification(notification, &block)
    notification_sent = false

    subscription = lambda do |*args|
      notification_sent = true
    end

    ActiveSupport::Notifications.subscribed(subscription, notification) do
      block.call if block_given?
    end

    assert_not notification_sent, "#{notification} notification was sent"
  end
end
