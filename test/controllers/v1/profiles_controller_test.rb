# frozen_string_literal: true

require 'test_helper'

module V1
  # Integration test of authentication
  class ProfilesAuthenticationTest < ActionDispatch::IntegrationTest
    context 'disabled rbac via cert based auth' do
      should 'disallows access when inventory errors' do
        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': '1234',
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        HostInventoryApi.any_instance.expects(:hosts)
                        .raises(Faraday::Error.new(''))
        get profiles_url, headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :forbidden
      end

      should 'allow access to profiles#index' do
        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': '1234',
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        HostInventoryApi.any_instance
                        .expects(:hosts)
                        .returns('results' => [:foo])
        get profiles_url, headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :success
      end

      should 'disallow access to profiles#index with invalid identity' do
        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': '1234',
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        HostInventoryApi.any_instance.expects(:hosts).returns('results' => [])
        get profiles_url, headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :forbidden
      end

      should 'allow access to profiles#tailoring_file' do
        account = FactoryBot.create(:account)
        profile = FactoryBot.create(:canonical_profile, account: account)

        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': account.account_number,
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        HostInventoryApi.any_instance
                        .expects(:hosts)
                        .returns('results' => [:foo])
        get tailoring_file_profile_url(profile.id),
            headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :success
      end

      should 'disallow access to profiles#tailoring_file' \
             ' with invalid identity' do
        account = FactoryBot.create(:account)
        profile = FactoryBot.create(:canonical_profile, account: account)

        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': account.account_number,
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        HostInventoryApi.any_instance.expects(:hosts).returns('results' => [])
        get tailoring_file_profile_url(profile),
            headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :forbidden
      end

      should 'disallow access to profiles#show' do
        HostInventoryApi.any_instance.expects(:hosts).never
        account = FactoryBot.create(:account)
        profile = FactoryBot.create(:profile, account: account)

        encoded_header = Base64.encode64(
          {
            'identity': {
              'account_number': account.account_number,
              'auth_type': IdentityHeader::CERT_AUTH
            },
            'entitlements':
            {
              'insights': {
                'is_entitled': true
              }
            }
          }.to_json
        )
        get profile_url(profile),
            headers: { 'X-RH-IDENTITY': encoded_header }
        assert_response :forbidden
      end
    end
  end

  class ProfilesControllerTest < ActionDispatch::IntegrationTest
    setup do
      ProfilesController.any_instance.stubs(:authenticate_user).yields
      User.current = FactoryBot.create(:user)
    end

    def params(data)
      { data: data }
    end

    def parsed_data
      response.parsed_body.dig('data')
    end

    class TailoringFileTest < ProfilesControllerTest
      test 'tailoring_file with a canonical profile returns no content' do
        profile = FactoryBot.create(:canonical_profile, :with_rules)
        get tailoring_file_v1_profile_url(profile.id)
        assert_response :no_content
      end

      test 'tailoring_file with a noncanonical profile matching its parent'\
        'returns no content' do
        profile = FactoryBot.create(:profile, :with_rules)
        get tailoring_file_v1_profile_url(profile.id)
        assert_response :no_content
      end

      test 'tailoring_file with a noncanonical profile '\
        'returns tailoring file' do
        profile = FactoryBot.create(:profile, :with_rules)

        profile.rules.delete(profile.rules.sample)

        get tailoring_file_v1_profile_url(profile.id)
        assert_response :success
        assert_equal Mime[:xml].to_s, @response.content_type
        assert_audited 'Sent computed tailoring file'
        assert_audited profile.id
      end
    end

    class IndexTest < ProfilesControllerTest
      test 'policy_profile_id is exposed' do
        profile = FactoryBot.create(:profile)
        get v1_profiles_url
        assert_response :success

        profiles = response.parsed_body
        assert_equal 1, profiles['data'].length
        assert_equal profile.policy_profile_id,
                     profiles.dig('data', 0, 'attributes', 'policy_profile_id')
      end

      test 'profiles are sorted by score by default' do
        p1 = FactoryBot.create(:profile, name: 'a')
        p2 = FactoryBot.create(:profile, name: 'b')
        FactoryBot.create(:test_result, profile: p1, score: 0.3)
        FactoryBot.create(:test_result, profile: p2, score: 0.5)

        get v1_profiles_url, params: {
          search: 'canonical=false'
        }

        assert_response :success

        profiles = response.parsed_body

        assert_equal(%w[a b], profiles['data'].map do |profile|
          profile['attributes']['name']
        end)
      end

      test 'search string properly escaped' do
        FactoryBot.create(:profile, name: 'a_c')
        FactoryBot.create(:profile, name: 'abc')

        get v1_profiles_url, params: {
          search: 'canonical=false and name~a_c'
        }

        assert_response :success

        profiles = response.parsed_body

        assert_equal 1, profiles['data'].count
        assert_equal(['a_c'], profiles['data'].map do |profile|
          profile['attributes']['name']
        end)
      end

      test 'correct searching for IN operator' do
        FactoryBot.create(:profile, name: 'abc')
        FactoryBot.create(:profile, name: 'def')
        FactoryBot.create(:profile, name: 'ghi')

        get v1_profiles_url, params: {
          search: 'canonical=false and name ^ (abc def)'
        }

        assert_response :success

        profiles = response.parsed_body

        assert_equal 2, profiles['data'].count
        assert_equal(%w[abc def], profiles['data'].map do |profile|
          profile['attributes']['name']
        end.sort)
      end

      test 'profiles can be sorted by a single dimension' do
        p1 = FactoryBot.create(:profile, name: 'a')
        p2 = FactoryBot.create(:profile, name: 'b')
        FactoryBot.create(:test_result, profile: p1, score: 0.4)
        FactoryBot.create(:test_result, profile: p1, score: 0.1)
        FactoryBot.create(:test_result, profile: p2, score: 0.5)

        get v1_profiles_url, params: {
          search: 'canonical=false',
          sort_by: 'name:desc'
        }

        assert_response :success

        profiles = response.parsed_body

        assert_equal(%w[b a], profiles['data'].map do |profile|
          profile['attributes']['name']
        end)
      end

      test 'profiles can be sorted' do
        FactoryBot.create(:profile, name: 'a', os_minor_version: '1')
        FactoryBot.create(:profile, name: 'a', os_minor_version: '2')
        FactoryBot.create(:profile, name: 'b', os_minor_version: '3')

        get v1_profiles_url, params: {
          search: 'canonical=false',
          sort_by: %w[name os_minor_version:desc]
        }
        assert_response :success

        profiles = response.parsed_body

        assert_equal(%w[2 1 3], profiles['data'].map do |profile|
          profile['attributes']['os_minor_version']
        end)
      end

      test 'sorting by name delegates to policy' do
        FactoryBot.create(:profile, name: 'foo')
        FactoryBot.create(
          :profile,
          name: 'foo',
          policy: FactoryBot.create(:policy, name: 'bar')
        )
        FactoryBot.create(
          :profile,
          name: 'foo',
          policy: FactoryBot.create(:policy, name: 'asd')
        )

        get v1_profiles_url, params: {
          search: 'canonical=false',
          sort_by: %w[name]
        }

        profiles = JSON.parse(response.body)

        assert_equal(%w[asd bar foo], profiles['data'].map do |profile|
          profile['attributes']['name']
        end)
      end

      should 'fail if wrong sort order is set' do
        get v1_profiles_url, params: { sort_by: ['name:foo'] }
        assert_response :unprocessable_entity
      end

      should 'fail if sorting by wrong column' do
        get v1_profiles_url, params: { sort_by: ['foo'] }
        assert_response :unprocessable_entity
      end

      test 'external profiles can be requested' do
        profile = FactoryBot.create(:profile, external: true)
        search_query = 'external=true'
        get v1_profiles_url, params: { search: search_query }
        assert_response :success

        profiles = response.parsed_body
        assert_equal 1, profiles['data'].length
        assert_equal profile.id, profiles['data'].first['id']
      end

      test 'canonical profiles can be requested' do
        profile = FactoryBot.create(:profile)
        search_query = 'canonical=true'
        get v1_profiles_url, params: { search: search_query }
        assert_response :success

        profiles = response.parsed_body
        assert_equal 1, profiles['data'].length
        assert_equal profile.parent_profile.id, profiles['data'].first['id']
      end

      test 'does not contain external or canonical profiles by default' do
        get v1_profiles_url
        assert_response :success

        profiles = response.parsed_body
        assert_empty profiles['data']
      end

      test 'returns the policy_type attribute' do
        profile = FactoryBot.create(:profile)

        get v1_profiles_url
        assert_response :success

        profiles = response.parsed_body
        assert_equal profile.parent_profile.name,
                     profiles.dig('data', 0, 'attributes', 'policy_type')
      end

      test 'only contain internal profiles by default' do
        profile = FactoryBot.create(:profile)

        get v1_profiles_url
        assert_response :success

        profiles = response.parsed_body
        assert_equal profile.id, profiles['data'].first['id']
      end

      test 'all profile types can be requested at the same time' do
        parent = FactoryBot.create(:canonical_profile)
        internal = FactoryBot.create(:profile, parent_profile: parent)
        external = FactoryBot.create(:profile, parent_profile: parent,
                                               external: true)

        search_query = 'canonical=true or canonical=false '\
                       'or external=false or external=true'
        get v1_profiles_url, params: { search: search_query }
        assert_response :success

        profiles = response.parsed_body
        returned_ids = profiles['data'].map { |p| p['id'] }
        assert_equal 3, profiles['data'].length
        assert_includes returned_ids, internal.id
        assert_includes returned_ids, external.id
        assert_includes returned_ids, parent.id
      end

      test 'returns all policy hosts' do
        hosts = FactoryBot.create_list(:host, 2)
        host_ids = hosts.map(&:id).sort

        policy = FactoryBot.create(:policy)

        profile = FactoryBot.create(:profile, policy: policy,
                                              account: policy.account)

        FactoryBot.create(:test_result, host: hosts.first, profile: profile)

        FactoryBot.create(
          :test_result,
          host: hosts.last,
          profile: FactoryBot.create(
            :profile,
            policy: policy,
            account: policy.account,
            parent_profile: profile.parent_profile,
            external: true
          )
        )

        policy.stubs(:supported_os_minor_versions).returns(hosts.map(&:os_minor_version).map(&:to_s))
        policy.hosts = hosts

        search_query = 'canonical=false'

        get v1_profiles_url, params: { search: search_query }
        assert_response :success

        profiles = response.parsed_body['data']
        assert_equal 2, profiles.length

        profiles.each do |returned_profile|
          returned_hosts =
            returned_profile.dig('relationships', 'hosts', 'data')
                            .map { |h| h['id'] }
                            .sort
          assert_equal host_ids, returned_hosts
        end
      end

      test 'returns test result hosts for external profiles' do
        host = FactoryBot.create(:host)
        profile = FactoryBot.create(:profile, external: true)
        FactoryBot.create(:test_result, host: host, profile: profile)
        profile.policy.stubs(:initial_profile).returns(profile)
        profile.policy.stubs(:supported_os_minor_versions).returns([host.os_minor_version.to_s])
        profile.policy.hosts = [host]

        get v1_profiles_url, params: { search: 'external = true' }
        assert_response :success

        returned_profiles = response.parsed_body['data']

        assert_equal 1, returned_profiles.length

        returned_hosts =
          returned_profiles.first
                           .dig('relationships', 'hosts', 'data')
                           .map { |h| h['id'] }
                           .sort
        assert_equal 1, returned_hosts.length
        assert_includes(returned_hosts, host.id)
      end
    end

    class ShowTest < ProfilesControllerTest
      setup do
        @profile = FactoryBot.create(:profile)
      end

      test 'a single profile may be requested' do
        get v1_profile_url(@profile.id)
        assert_response :success

        body = response.parsed_body
        assert_equal @profile.policy_profile_id,
                     body.dig('data', 'attributes', 'policy_profile_id')
      end

      test 'os_minor_version is serialized' do
        get v1_profile_url(@profile.id)
        assert_response :success

        assert_not_nil response.parsed_body.dig('data', 'attributes',
                                                'os_minor_version')
      end
    end

    class DestroyTest < ProfilesControllerTest
      require 'sidekiq/testing'
      Sidekiq::Testing.inline!

      setup do
        @profile = FactoryBot.create(:profile)
      end

      test 'destroy an existing, accessible profile' do
        profile_id = @profile.id
        assert_difference('Profile.count' => -1, 'Policy.count' => -1) do
          delete profile_path(profile_id)
        end
        assert_response :success
        assert_equal 202, response.status, 'Response should be 202 accepted'
        assert_equal profile_id, response.parsed_body.dig('data', 'id'),
                     'Profile ID did not match deleted profile'
        assert_audited 'Removed profile'
        assert_audited profile_id
      end

      test 'v1 destroy an existing, accessible profile' do
        profile_id = @profile.id
        assert_difference('Profile.count' => -1, 'Policy.count' => -1) do
          delete v1_profile_path(profile_id)
        end
        assert_response :success
        assert_equal 202, response.status, 'Response should be 202 accepted'
        assert_equal profile_id, response.parsed_body.dig('data', 'id'),
                     'Profile ID did not match deleted profile'
        assert_audited 'Removed profile'
        assert_audited profile_id
      end

      test 'destroing internal profile detroys its policy with profiles' do
        FactoryBot.create(
          :profile,
          account: @profile.account,
          external: true,
          policy: @profile.policy
        )

        profile_id = @profile.id
        assert_difference('Profile.count' => -2, 'Policy.count' => -1) do
          delete v1_profile_path(profile_id)
        end
        assert_response :success
        assert_equal 202, response.status, 'Response should be 202 accepted'
        assert_equal profile_id, response.parsed_body.dig('data', 'id'),
                     'Profile ID did not match deleted profile'
        assert_audited 'Removed profile'
        assert_audited profile_id
        assert_audited @profile.policy.id
        assert_audited 'Autoremoved policy'
        assert_audited 'with the initial/main profile'
      end

      test 'destroy a non-existant profile' do
        profile_id = @profile.id
        @profile.destroy
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          delete v1_profile_path(profile_id)
        end
        assert_response :not_found
      end

      test 'destroy an existing, not accessible profile' do
        profile = FactoryBot.create(
          :profile,
          account: FactoryBot.create(:account)
        )
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          delete v1_profile_path(profile.id)
        end
        assert_response :not_found
      end

      test 'destroy an existing, accessible profile that is not authorized '\
           'to be deleted' do
        profile = FactoryBot.create(
          :canonical_profile,
          account: FactoryBot.create(:account)
        )

        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          delete v1_profile_path(profile.id)
        end
        assert_response :forbidden
      end
    end

    class CreateTest < ProfilesControllerTest
      NAME = 'A new name'
      DESCRIPTION = 'A new description'
      COMPLIANCE_THRESHOLD = 93.5
      BUSINESS_OBJECTIVE = 'LATAM Expansion'

      test 'create without data' do
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: { data: {} }
        end
        assert_response :unprocessable_entity
        assert_match 'param is missing or the value is empty: data',
                     response.parsed_body.dig('errors', 0)
      end

      test 'create with invalid data' do
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: { data: 'foo' }
        end
        assert_response :unprocessable_entity
        assert_match 'data must be a hash',
                     response.parsed_body.dig('errors', 0)
      end

      test 'create with empty attributes' do
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: { data: { attributes: {} } }
        end
        assert_response :unprocessable_entity
        assert_match 'param is missing or the value is empty: data',
                     response.parsed_body.dig('errors', 0)
      end

      test 'create with invalid attributes' do
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: { data: { attributes: 'invalid' } }
        end
        assert_response :unprocessable_entity
        assert_match 'attributes must be a hash',
                     response.parsed_body.dig('errors', 0)
      end

      test 'create with empty parent_profile_id' do
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: params(
            attributes: { parent_profile_id: '' }
          )
        end
        assert_response :unprocessable_entity
        assert_match 'param is missing or the value is empty: '\
                     'parent_profile_id',
                     response.parsed_body.dig('errors', 0)
      end

      test 'create with an unfound parent_profile_id' do
        post profiles_path, params: params(
          attributes: { parent_profile_id: 'notfound' }
        )
        assert_response :not_found
      end

      test 'create with a found parent_profile_id but existing ref_id '\
           'in the account' do
        profile = FactoryBot.create(:profile)
        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: profile.parent_profile.id,
              ref_id: profile.ref_id
            }
          )
        end
        assert_response :not_acceptable
      end

      test 'create with a found parent_profile_id and nonexisting ref_id '\
           'in the account' do
        parent = FactoryBot.create(:canonical_profile)
        assert_difference('Profile.count' => 1, 'Policy.count' => 1) do
          post profiles_path, params: params(
            attributes: { parent_profile_id: parent.id }
          )
          assert_response :created
        end
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_audited 'Created policy'
      end

      test 'create with an exisiting profile type for a major OS' do
        profile = FactoryBot.create(:profile)

        assert_difference('Profile.count' => 0, 'Policy.count' => 0) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: profile.parent_profile.id
            }
          )
        end
        assert_response :not_acceptable
      end

      test 'create with a business objective' do
        parent = FactoryBot.create(:canonical_profile)

        assert_difference('Profile.count' => 1, 'Policy.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id,
              business_objective: BUSINESS_OBJECTIVE
            }
          )
          assert_response :created
        end
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal BUSINESS_OBJECTIVE,
                     parsed_data.dig('attributes', 'business_objective')
        assert_audited 'Created policy'
        assert_audited 'Created Business Objective'
      end

      test 'create with some customized profile attributes' do
        parent = FactoryBot.create(:canonical_profile)

        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id,
              name: NAME, description: DESCRIPTION
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal NAME, parsed_data.dig('attributes', 'name')
        assert_equal DESCRIPTION, parsed_data.dig('attributes', 'description')
        assert_audited 'Created policy'
      end

      test 'create with all customized profile attributes' do
        parent = FactoryBot.create(:canonical_profile)

        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id,
              name: NAME, description: DESCRIPTION,
              compliance_threshold: COMPLIANCE_THRESHOLD,
              business_objective: BUSINESS_OBJECTIVE
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal NAME, parsed_data.dig('attributes', 'name')
        assert_equal DESCRIPTION, parsed_data.dig('attributes', 'description')
        assert_equal COMPLIANCE_THRESHOLD,
                     parsed_data.dig('attributes', 'compliance_threshold')
        assert_equal BUSINESS_OBJECTIVE,
                     parsed_data.dig('attributes', 'business_objective')
        assert_audited 'Created policy'
      end

      test 'create copies rules from the parent profile' do
        parent = FactoryBot.create(:canonical_profile, :with_rules)

        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal(
          Set.new(parent.rule_ids),
          Set.new(parsed_data.dig('relationships', 'rules', 'data')
                             .map { |r| r['id'] })
        )
        assert_audited 'Created policy'
      end

      test 'create allows custom rules' do
        parent = FactoryBot.create(:canonical_profile, :with_rules)
        rule_ids = parent.benchmark.rules.pluck(:id)

        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            },
            relationships: {
              rules: {
                data: rule_ids.map do |id|
                  { id: id, type: 'rule' }
                end
              }
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal(
          Set.new(rule_ids),
          Set.new(parsed_data.dig('relationships', 'rules', 'data')
                             .map { |r| r['id'] })
        )
        assert_audited 'Created policy'
        assert_audited 'Updated tailoring of profile'
        assert_audited "#{rule_ids.count} rules added"
        assert_audited '0 rules removed'
      end

      test 'create only adds custom rules from the parent profile benchmark' do
        parent = FactoryBot.create(
          :canonical_profile,
          :with_rules,
          rule_count: 1
        )
        extra_rule = FactoryBot.create(
          :canonical_profile,
          :with_rules,
          rule_count: 1
        ).rules

        assert(parent.benchmark.rules.one?)

        rule_ids = parent.rules.pluck(:id) + extra_rule.pluck(:id)
        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            },
            relationships: {
              rules: {
                data: rule_ids.map do |id|
                  { id: id, type: 'rule' }
                end
              }
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal(
          Set.new(parent.benchmark.rule_ids),
          Set.new(parsed_data.dig('relationships', 'rules', 'data')
                             .map { |r| r['id'] })
        )
        assert_audited 'Created policy'
        assert_audited 'Updated tailoring of profile'
        assert_audited "#{extra_rule.count} rules added"
        assert_audited '0 rules removed'
      end

      test 'create only adds custom rules from the parent profile benchmark'\
           'and defaults to parent profile rules' do
        parent = FactoryBot.create(
          :canonical_profile,
          :with_rules,
          rule_count: 1
        )

        extra_rule = FactoryBot.create(
          :canonical_profile,
          :with_rules,
          rule_count: 1
        ).rules

        assert(parent.benchmark.rules.one?)
        rule_ids = extra_rule.pluck(:id)
        assert_difference('Profile.count' => 1) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            },
            relationships: {
              rules: {
                data: rule_ids.map do |id|
                  { id: id, type: 'rule' }
                end
              }
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal(
          Set.new(parent.rule_ids),
          Set.new(parsed_data.dig('relationships', 'rules', 'data')
                             .map { |r| r['id'] })
        )
        assert_audited 'Created policy'
        assert_audited 'Updated tailoring of profile'
        assert_audited "#{extra_rule.count} rules added"
        assert_audited '0 rules removed'
      end

      test 'create allows hosts relationship' do
        hosts = FactoryBot.create_list(:host, 2)
        parent = FactoryBot.create(:canonical_profile, upstream: false)

        SupportedSsg.stubs(:by_ssg_version).returns(
          parent.benchmark.version => hosts.map do |host|
            SupportedSsg.new(
              os_major_version: host.os_major_version.to_s,
              os_minor_version: host.os_minor_version.to_s
            )
          end
        )

        assert_empty(parent.hosts)
        assert_difference('PolicyHost.count', hosts.count) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            },
            relationships: {
              hosts: {
                data: hosts.map do |host|
                  { id: host.id, type: 'host' }
                end
              }
            }
          )
        end
        assert_response :created
        assert_equal User.current.account.id,
                     parsed_data.dig('relationships', 'account', 'data', 'id')
        assert_equal(
          Set.new(hosts.pluck(:id)),
          Set.new(parsed_data.dig('relationships', 'hosts', 'data')
                             .map { |r| r['id'] })
        )
        assert_audited 'Created policy'
        assert_audited 'Updated systems assignment on policy'
        assert_audited "#{hosts.count} added"
        assert_audited '0 removed'
      end

      test 'create fails with unsupported hosts' do
        hosts = FactoryBot.create_list(:host, 2)
        SupportedSsg.stubs(:by_ssg_version).returns({})
        parent = FactoryBot.create(:canonical_profile)
        assert_empty(parent.hosts)
        assert_difference('PolicyHost.count', 0) do
          post profiles_path, params: params(
            attributes: {
              parent_profile_id: parent.id
            },
            relationships: {
              hosts: {
                data: hosts.map do |host|
                  { id: host.id, type: 'host' }
                end
              }
            }
          )
        end
        assert_response :not_acceptable
      end
    end

    class UpdateTest < ProfilesControllerTest
      NAME = 'A new name'
      DESCRIPTION = 'A new description'
      COMPLIANCE_THRESHOLD = 93.5
      BUSINESS_OBJECTIVE = 'LATAM Expansion'

      setup do
        @profile = FactoryBot.create(:profile, :with_rules, upstream: false)
      end

      test 'update without data' do
        patch v1_profile_path(@profile.id), params: params({})
        assert_response :unprocessable_entity
        assert_match 'param is missing or the value is empty: data',
                     response.parsed_body.dig('errors', 0)
      end

      test 'update with invalid data' do
        patch profile_path(@profile.id), params: params('foo')
        assert_response :unprocessable_entity
        assert_match 'data must be a hash',
                     response.parsed_body.dig('errors', 0)
      end

      test 'update with invalid attributes' do
        patch profile_path(@profile.id), params: params(attributes: 'foo')
        assert_response :unprocessable_entity
        assert_match 'attributes must be a hash',
                     response.parsed_body.dig('errors', 0)
      end

      test 'update with a single attribute' do
        assert_difference(
          "Policy.where(description: '#{DESCRIPTION}').count" => 1
        ) do
          patch profile_path(@profile.id), params: params(
            attributes: { description: DESCRIPTION }
          )
        end
        assert_response :success
        assert_equal DESCRIPTION, @profile.policy.reload.description
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
      end

      test 'update with multiple attributes' do
        assert_difference('BusinessObjective.count' => 1) do
          patch profile_path(@profile.id), params: params(
            attributes: {
              description: DESCRIPTION,
              compliance_threshold: COMPLIANCE_THRESHOLD,
              business_objective: BUSINESS_OBJECTIVE
            }
          )
        end
        assert_response :success
        assert_equal DESCRIPTION, @profile.policy.reload.description
        assert_equal COMPLIANCE_THRESHOLD, @profile.compliance_threshold
        assert_equal BUSINESS_OBJECTIVE, @profile.business_objective.title
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
      end

      test 'update with attributes and rules relationships' do
        @profile.rules = []
        benchmark_rules = @profile.benchmark.rules
        assert_difference(
          '@profile.rules.count' => benchmark_rules.count
        ) do
          patch profile_path(@profile.id), params: params(
            attributes: {
              business_objective: BUSINESS_OBJECTIVE
            },
            relationships: {
              rules: {
                data: benchmark_rules.map do |rule|
                  { id: rule.id, type: 'rule' }
                end
              }
            }
          )
        end
        assert_response :success
        assert_equal BUSINESS_OBJECTIVE,
                     @profile.reload.business_objective.title
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
        assert_audited 'Updated tailoring of profile'
        assert_audited "#{benchmark_rules.count} rules added"
        assert_audited '0 rules removed'
      end

      test 'update to remove rules relationships' do
        benchmark_rules = @profile.benchmark.rules
        assert_difference(
          '@profile.reload.rules.count' => -1
        ) do
          patch profile_path(@profile.id), params: params(
            attributes: {
              business_objective: BUSINESS_OBJECTIVE
            },
            relationships: {
              rules: {
                data: benchmark_rules[0...-1].map do |rule|
                  { id: rule.id, type: 'rule' }
                end
              }
            }
          )
        end
        assert_response :success
        assert_equal BUSINESS_OBJECTIVE,
                     @profile.reload.business_objective.title
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
        assert_audited 'Updated tailoring of profile'
        assert_audited '0 rules added, 1 rules removed'
      end

      test 'update to update hosts relationships' do
        hosts = FactoryBot.create_list(:host, 2)

        SupportedSsg.stubs(:by_ssg_version).returns(
          @profile.benchmark.version => hosts.map do |host|
            SupportedSsg.new(
              os_major_version: host.os_major_version.to_s,
              os_minor_version: host.os_minor_version.to_s
            )
          end
        )

        @profile.policy.update!(hosts: hosts[0...-1])
        assert_difference('@profile.policy.reload.hosts.count' => 0) do
          patch profile_path(@profile.id), params: params(
            attributes: {},
            relationships: {
              hosts: {
                data: hosts[1..-1].map do |host|
                  { id: host.id, type: 'host' }
                end
              }
            }
          )
        end
        assert_response :success
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
        assert_audited 'Updated systems assignment on policy'
        assert_audited '1 added, 1 removed'
      end

      test 'update to remove hosts relationships' do
        hosts = FactoryBot.create_list(:host, 2)

        SupportedSsg.stubs(:by_ssg_version).returns(
          @profile.benchmark.version => hosts.map do |host|
            SupportedSsg.new(
              os_major_version: host.os_major_version.to_s,
              os_minor_version: host.os_minor_version.to_s
            )
          end
        )

        @profile.policy.update!(hosts: hosts)
        assert_difference(
          '@profile.policy.reload.hosts.count' => -1
        ) do
          patch profile_path(@profile.id), params: params(
            attributes: {},
            relationships: {
              hosts: {
                data: hosts[0...-1].map do |host|
                  { id: host.id, type: 'host' }
                end
              }
            }
          )
        end
        assert_response :success
        assert_audited 'Updated profile'
        assert_audited @profile.id
        assert_audited @profile.policy.id
        assert_audited 'Updated systems assignment on policy'
        assert_audited '0 added, 1 removed'
      end
    end
  end
end
