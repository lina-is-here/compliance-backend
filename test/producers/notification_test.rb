# frozen_string_literal: true

require 'test_helper'

class NofiticationTest < ActiveSupport::TestCase
  class MockNotification < Notification
    def self.build_context(**_kwargs)
      {}
    end

    def self.build_events(**_kwargs)
      []
    end
  end

  setup do
    @acc = FactoryBot.create(:account)
  end

  test 'handles missing kafka config' do
    assert_nil MockNotification.deliver(account_number: @acc.account_number)
  end

  test 'delivers messages to the notifications topic' do
    kafka = mock('kafka')
    MockNotification.stubs(:kafka).returns(kafka)
    kafka.expects(:deliver_message)
         .with(anything, topic: 'platform.notifications.ingress')
    MockNotification.deliver(account_number: @acc.account_number)
  end

  test 'handles delivery issues' do
    kafka = mock('kafka')
    Kafka.stubs(:new).returns(kafka)
    MockNotification.stubs(:kafka).returns(kafka)
    kafka.expects(:deliver_message)
         .with(anything, topic: 'platform.notifications.ingress')
         .raises(Kafka::DeliveryFailed.new(nil, nil))

    assert_nothing_raised do
      MockNotification.deliver(account_number: @acc.account_number)
    end
  end
end
