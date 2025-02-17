# frozen_string_literal: true

require 'test_helper'

class ProfileQueryTest < ActiveSupport::TestCase
  setup do
    PolicyHost.any_instance.stubs(:host_supported?).returns(true)
    @user = FactoryBot.create(:user)
    @profile = FactoryBot.create(
      :profile,
      :with_rules,
      rule_count: 2,
      account: @user.account
    )
  end

  test 'query profile owned by the user' do
    query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              name
              refId
          }
      }
    GRAPHQL

    result = Schema.execute(
      query,
      variables: { id: @profile.id },
      context: { current_user: @user }
    )

    assert_equal @profile.name, result['data']['profile']['name']
    assert_equal @profile.ref_id, result['data']['profile']['refId']
  end

  test 'query profile policyType' do
    query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              name
              refId
              policyType
          }
      }
    GRAPHQL

    result = Schema.execute(
      query,
      variables: { id: @profile.id },
      context: { current_user: @user }
    )

    assert_equal @profile.parent_profile.name,
                 result['data']['profile']['policyType']
  end

  test 'query profile parentProfileId' do
    query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              parentProfileId
          }
      }
    GRAPHQL

    result = Schema.execute(
      query,
      variables: { id: @profile.id },
      context: { current_user: @user }
    )

    assert_equal @profile.parent_profile_id,
                 result['data']['profile']['parentProfileId']
  end

  test 'query profile with SSG version' do
    query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              refId
              ssgVersion
          }
      }
    GRAPHQL

    assert @profile.benchmark.version

    result = Schema.execute(
      query,
      variables: { id: @profile.id },
      context: { current_user: @user }
    )

    assert_equal @profile.ref_id, result['data']['profile']['refId']
    assert_equal @profile.benchmark.version,
                 result['data']['profile']['ssgVersion']
  end

  test 'query profile owned by another user' do
    query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              name
              refId
          }
      }
    GRAPHQL

    @profile.update!(account: FactoryBot.create(:account))

    assert_raises(Pundit::NotAuthorizedError) do
      Schema.execute(
        query,
        variables: { id: @profile.id },
        context: { current_user: @user }
      )
    end
  end

  context 'policy profiles' do
    setup do
      @hosts = FactoryBot.create_list(
        :host,
        2,
        account: @user.account.account_number
      )

      @profile2 = FactoryBot.create(
        :profile,
        policy: @profile.policy,
        ref_id: @profile.ref_id,
        name: @profile.name,
        account: @user.account,
        external: true
      )

      @profile.policy.update!(hosts: @hosts)
    end

    should 'query profile with a policy owned by the user' do
      query = <<-GRAPHQL
        query Profile($id: String!){
            profile(id: $id) {
                id
                name
                refId
                policy {
                  id
                  name
                  refId
                }
            }
        }
      GRAPHQL

      result = Schema.execute(
        query,
        variables: { id: @profile2.id },
        context: { current_user: @user }
      )

      assert_equal @profile.policy.name, result['data']['profile']['name']
      assert_equal @profile2.ref_id, result['data']['profile']['refId']

      assert_equal @profile.id,
                   result['data']['profile']['policy']['id']
      assert_equal @profile.ref_id,
                   result['data']['profile']['policy']['refId']
      assert_equal @profile.name,
                   result['data']['profile']['policy']['name']
    end

    should 'query profile with a policy profiles using first policy profile' \
    ' owned by the user' do
      query = <<-GRAPHQL
      query Profile($id: String!){
          profile(id: $id) {
              id
              name
              description
              refId
              policy {
                profiles {
                  id
                  refId
                  name
                  description
                }
              }
          }
      }
      GRAPHQL

      result = Schema.execute(
        query,
        variables: { id: @profile.id },
        context: { current_user: @user }
      )

      assert_equal @profile.policy.name, result['data']['profile']['name']
      assert_equal @profile.policy.description,
                   result['data']['profile']['description']
      assert_equal @profile.ref_id, result['data']['profile']['refId']

      returned_profiles = result['data']['profile']['policy']['profiles']
      assert_equal returned_profiles.count, 2

      policy_profile =
        returned_profiles.find { |rp| rp['id'] == @profile.id }
      assert_equal @profile.ref_id, policy_profile['refId']
      assert_equal @profile.policy.name, policy_profile['name']
      assert_equal @profile.policy.description, policy_profile['description']

      second_profile =
        returned_profiles.find { |rp| rp['id'] == @profile2.id }
      assert_equal @profile2.ref_id, second_profile['refId']
      assert_equal @profile.policy.name, second_profile['name']
      assert_equal @profile.policy.description, second_profile['description']
    end

    should 'query profile with a policy profiles using any policy profile' \
           ' owned by the user' do
      query = <<-GRAPHQL
        query Profile($id: String!){
            profile(id: $id) {
                id
                name
                description
                refId
                policy {
                  profiles {
                    id
                    refId
                    name
                    description
                  }
                }
            }
        }
      GRAPHQL

      result = Schema.execute(
        query,
        variables: { id: @profile2.id },
        context: { current_user: @user }
      )

      assert_equal @profile.policy.name, result['data']['profile']['name']
      assert_equal @profile2.ref_id, result['data']['profile']['refId']

      returned_profiles = result['data']['profile']['policy']['profiles']
      assert_equal returned_profiles.count, 2

      policy_profile =
        returned_profiles.find { |rp| rp['id'] == @profile.id }
      assert_equal @profile.ref_id, policy_profile['refId']
      assert_equal @profile.policy.name, policy_profile['name']
      assert_equal @profile.policy.description, policy_profile['description']

      second_profile =
        returned_profiles.find { |rp| rp['id'] == @profile2.id }
      assert_equal @profile2.ref_id, second_profile['refId']
      assert_equal @profile.policy.name, second_profile['name']
      assert_equal @profile.policy.description, second_profile['description']
    end

    should 'sort results' do
      query = <<-GRAPHQL
      {
        profiles(search: "canonical=false", sortBy: ["name", "osMinorVersion:desc"]) {
          edges {
            node {
              id
              name
              osMinorVersion
            }
          }
        }
      }
      GRAPHQL

      @profile.update!(os_minor_version: 2, name: 'foo')
      @profile2.update!(os_minor_version: 3, name: 'foo')

      result = Schema.execute(
        query,
        variables: {},
        context: { current_user: @user }
      )

      profiles = result['data']['profiles']['edges']

      assert_equal '3', profiles.first['node']['osMinorVersion']
      assert_equal '2', profiles.second['node']['osMinorVersion']
    end

    should 'correctly escape searched string' do
      query = <<-GRAPHQL
      {
        profiles(search: "canonical=false and name~a_c") {
          edges {
            node {
              id
              name
            }
          }
        }
      }
      GRAPHQL

      @profile.update!(name: 'a_c')
      @profile2.update!(name: 'abc')

      result = Schema.execute(
        query,
        variables: {},
        context: { current_user: @user }
      )

      profiles = result['data']['profiles']['edges']
      assert_equal 1, profiles.count
      assert_equal @profile.id, profiles.first['node']['id']
    end
  end
end
