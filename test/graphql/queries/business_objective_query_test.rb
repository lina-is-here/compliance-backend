# frozen_string_literal: true

require 'test_helper'

class BusinessObjectiveTest < ActiveSupport::TestCase
  test 'query host owned by the user' do
    query = <<-GRAPHQL
      {
          businessObjectives {
              id
              title
          }
      }
    GRAPHQL

    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, account: user.account)
    bo = FactoryBot.create(:business_objective)
    profile.policy.update!(business_objective: bo)

    result = Schema.execute(
      query,
      variables: {},
      context: { current_user: user }
    )

    assert_equal bo.id,
                 result['data']['businessObjectives'].first['id']
    assert_equal bo.title,
                 result['data']['businessObjectives'].first['title']
  end
end
