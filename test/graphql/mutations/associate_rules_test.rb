# frozen_string_literal: true

require 'test_helper'

class AssociateRulesMutationTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user)
    parent = FactoryBot.create(:canonical_profile, :with_rules, rule_count: 1)
    @profile = FactoryBot.create(
      :profile,
      account: @user.account,
      parent_profile: parent,
      benchmark: parent.benchmark
    )
    @rule = parent.rules.first
  end

  QUERY = <<-GRAPHQL
     mutation associateRules($input: associateRulesInput!) {
        associateRules(input: $input) {
           profile {
               id
           }
        }
     }
  GRAPHQL

  {
    ruleIds: :id,
    ruleRefIds: :ref_id
  }.each do |key, field|
    context key do
      should 'provide all required arguments' do
        assert_empty @profile.rules

        Schema.execute(
          QUERY,
          variables: { input: {
            id: @profile.id,
            key => [@rule.send(field)]
          } },
          context: { current_user: @user }
        )['data']['associateRules']['profile']

        assert_equal Set.new(@profile.reload.rules),
                     Set.new([@rule])
      end

      should 'removes rules from a profile' do
        profile = FactoryBot.create(
          :profile,
          :with_rules,
          account: @user.account,
          rule_count: 1
        )
        profile.parent_profile.update!(rules: [])

        assert_not_empty profile.rules

        Schema.execute(
          QUERY,
          variables: { input: {
            id: profile.id,
            key => []
          } },
          context: { current_user: @user }
        )['data']['associateRules']['profile']

        assert_empty profile.reload.rules
        assert_audited 'Updated rule assignments of profile'
        assert_audited profile.id
      end
    end
  end

  test 'fails if no rules are passed' do
    assert_raises ActionController::ParameterMissing do
      Schema.execute(
        QUERY,
        variables: { input: {
          id: @profile.id
        } },
        context: { current_user: @user }
      )['data']['associateRules']['profile']
    end
  end
end
