# frozen_string_literal: true

require 'test_helper'

module V1
  class BusinessObjectivesControllerTest < ActionDispatch::IntegrationTest
    setup do
      BusinessObjectivesController.any_instance.stubs(:authenticate_user).yields
      User.current = FactoryBot.create(:user)

      @bo1 = FactoryBot.create(:business_objective, title: 'a')
      @bo2 = FactoryBot.create(:business_objective, title: 'b')

      2.times do
        FactoryBot.create(
          :policy,
          account: User.current.account,
          business_objective: @bo1
        )
      end
    end

    context '#index' do
      should 'only list business objectives associated to owned policies' do
        get v1_business_objectives_path
        assert_response :success
        assert_equal @bo1.id, parsed_data&.first&.dig('id')
      end

      should 'be sorted by name' do
        FactoryBot.create(
          :policy,
          account: User.current.account,
          business_objective: @bo2
        )

        get v1_business_objectives_url, params: {
          sort_by: %w[title]
        }
        assert_response :success

        business_objectives = response.parsed_body['data']

        assert_equal([@bo1, @bo2].map(&:id), business_objectives.map do |bo|
          bo['id']
        end)
      end
    end

    context '#show' do
      should 'succeed' do
        get v1_business_objective_path(@bo1)
        assert_response :success
      end

      should 'not show business objectives not associated to owned policies' do
        get v1_business_objective_path(@bo2)
        assert_response :not_found
      end
    end
  end
end
