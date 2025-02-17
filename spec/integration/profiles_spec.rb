# frozen_string_literal: true

require 'swagger_helper'
require 'sidekiq/testing'

describe 'Profiles API' do
  before do
    @account = FactoryBot.create(:account)
    @policy = FactoryBot.create(:policy, account: @account)
    @parent = FactoryBot.create(:canonical_profile)
    @hosts = FactoryBot.create_list(
      :host, 2, account: @account.account_number, os_minor_version: 2
    )
    allow_any_instance_of(PolicyHost).to receive(:host_supported?).and_return(true)

    allow(@policy).to receive(:supported_os_minor_versions).and_return([2])
  end

  path "#{Settings.path_prefix}/#{Settings.app_name}/profiles" do
    get 'List all profiles' do
      tags 'profile'
      description 'Lists all profiles requested'
      operationId 'ListProfiles'

      content_types
      auth_header
      pagination_params
      search_params
      sort_params(Profile)

      include_param

      response '200', 'lists all profiles requested' do
        before do
          FactoryBot.create(:profile, account: @account, policy: @policy)
        end

        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:include) { '' } # work around buggy rswag
        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :array,
                   items: {
                     properties: {
                       type: { type: :string },
                       id: ref_schema('uuid'),
                       attributes: ref_schema('profile'),
                       relationships: ref_schema('profile_relationships')
                     }
                   }
                 }
               }
        after { |e| autogenerate_examples(e) }
        run_test!
      end

      response '200', 'lists all profiles requested filtered by OS' do
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:include) { '' } # work around buggy rswag
        let(:search) { 'os_major_version = 7' }
        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :array,
                   items: {
                     properties: {
                       type: { type: :string },
                       id: ref_schema('uuid'),
                       attributes: ref_schema('profile')
                     }
                   }
                 }
               }
        after { |e| autogenerate_examples(e) }
        run_test!
      end
    end

    post 'Create a profile' do
      tags 'profile'
      description 'Create a profile with the provided attributes'
      operationId 'CreateProfile'

      content_types
      auth_header

      parameter name: :data, in: :body, schema: {
        type: :object,
        properties: {
          type: { type: :string, example: 'profile' },
          data: {
            type: :object,
            properties: {
              type: { type: :string },
              attributes: ref_schema('profile'),
              relationships: ref_schema('profile_relationships')
            }
          }
        },
        example: {
          data: {
            attributes: {
              name: 'my custom profile',
              parent_profile_id: '0105a0f0-7379-4897-a891-f95cfb9ddf9c',
              description: 'This profile contains rules to ensure standard '\
              'security baseline\nof a Red Hat Enterprise Linux 7 '\
              'system. Regardless of your system\'s workload\nall '\
              'of these checks should pass.',
              compliance_threshold: 95.0,
              business_objective: 'APAC Expansion'
            },
            relationships: {
              rules: {
                data: [
                  { id: 'cc9afa66-3536-4d2e-bc8e-10111d13ec50', type: 'rule' },
                  { id: '06a19f0e-5c7a-4d54-bc66-e932a96bf954', type: 'rule' }
                ]
              },
              hosts: {
                data: [
                  { id: '6c3837ed-edac-4522-83a1-147af958f0f2', type: 'host' },
                  { id: 'f896d5e7-e44e-41cb-8e8e-96aab6d895d6', type: 'host' }
                ]
              }
            }
          }
        }
      }

      response '201', 'creates a profile' do
        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:include) { '' } # work around buggy rswag
        let(:data) do
          {
            data: {
              attributes: {
                parent_profile_id: @parent.id,
                name: 'A custom name',
                compliance_threshold: 93.5,
                business_objective: 'LATAM Expansion'
              },
              relationships: {
                rules: {
                  data: @parent.benchmark.rules.map do |rule|
                    { id: rule.id, type: 'rule' }
                  end
                },
                hosts: {
                  data: @hosts.map do |host|
                    { id: host.id, type: 'host' }
                  end
                }
              }
            }
          }
        end

        schema type: :object,
               properties: {
                 data: {
                   type: :object,
                   properties: {
                     type: { type: :string, example: 'profile' },
                     id: ref_schema('uuid'),
                     attributes: ref_schema('profile'),
                     relationships: ref_schema('profile_relationships')
                   }
                 }
               }

        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end
  end

  path "#{Settings.path_prefix}/#{Settings.app_name}/profiles/{id}" do
    get 'Retrieve a profile' do
      tags 'profile'
      description 'Retrieves data for a profile'
      operationId 'ShowProfile'

      content_types
      auth_header

      parameter name: :id, in: :path, type: :string
      include_param

      response '404', 'profile not found' do
        let(:id) { 'invalid' }
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:include) { '' } # work around buggy rswag
        after { |e| autogenerate_examples(e) }
        run_test!
      end

      response '200', 'retrieves a profile' do
        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:id) do
          FactoryBot.create(
            :profile,
            parent_profile: @profile,
            policy: @policy,
            account: @account
          ).id
        end
        let(:include) { '' } # work around buggy rswag
        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :object,
                   properties: {
                     type: { type: :string },
                     id: ref_schema('uuid'),
                     attributes: ref_schema('profile'),
                     relationships: ref_schema('profile_relationships')
                   }
                 }
               }
        after { |e| autogenerate_examples(e) }

        run_test!
      end

      response '200', 'retrieves a profile with included benchmark' do
        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:id) do
          @parent.id
        end
        let(:include) { 'benchmark' }
        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :object,
                   properties: {
                     type: { type: :string },
                     id: ref_schema('uuid'),
                     attributes: ref_schema('profile'),
                     relationships: ref_schema('profile_relationships')
                   },
                   relationships: ref_schema('profile_relationships')
                 },
                 included: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       type: { type: :string },
                       id: ref_schema('uuid'),
                       attributes: ref_schema('benchmark'),
                       relationships: { type: :object, properties: {} }
                     }
                   }
                 }
               }
        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end

    patch 'Update a profile' do
      tags 'profile'
      description 'Updates a profile'
      operationId 'UpdateProfile'

      content_types
      auth_header

      include_param
      parameter name: :id, in: :path, type: :string
      parameter name: :data, in: :body, schema: {
        type: :object,
        properties: {
          type: { type: :string, example: 'profile' },
          data: {
            type: :object,
            properties: {
              type: { type: :string },
              id: ref_schema('uuid'),
              attributes: ref_schema('profile'),
              relationships: ref_schema('profile_relationships')
            }
          }
        },
        example: {
          data: {
            id: '02596112-042c-4fc2-a321-787e98537452',
            attributes: {
              name: 'My updated custom profile',
              description: 'This profile contains rules to ensure standard '\
              'security baseline\nof a Red Hat Enterprise Linux 7 '\
              'system. Regardless of your system\'s workload\nall '\
              'of these checks should pass.',
              compliance_threshold: 92.0,
              business_objective: 'APAC Expansion'
            },
            relationships: {
              rules: {
                data: [
                  { id: 'cc9afa66-3536-4d2e-bc8e-10111d13ec50', type: 'rule' },
                  { id: '06a19f0e-5c7a-4d54-bc66-e932a96bf954', type: 'rule' }
                ]
              },
              hosts: {
                data: [
                  { id: '6c3837ed-edac-4522-83a1-147af958f0f2', type: 'host' },
                  { id: 'f896d5e7-e44e-41cb-8e8e-96aab6d895d6', type: 'host' }
                ]
              }
            }
          }
        }
      }

      response '404', 'profile not found' do
        let(:id) { 'invalid' }
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:include) { '' } # work around buggy rswag
        let(:data) {}

        after { |e| autogenerate_examples(e) }

        run_test!
      end

      response '200', 'updates a profile' do
        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:id) do
          FactoryBot.create(
            :profile,
            :with_rules,
            account: @account,
            policy: @policy,
            parent_profile: @parent
          ).id
        end
        let(:include) { '' } # work around buggy rswag
        let(:data) do
          {
            data: {
              attributes: {
                name: 'An updated custom name',
                compliance_threshold: 93.5,
                business_objective: 'APAC Expansion'
              },
              relationships: {
                rules: {
                  data: @parent.benchmark.rules.map do |rule|
                    { id: rule.id, type: 'rule' }
                  end
                },
                hosts: {
                  data: @hosts.map do |host|
                    { id: host.id, type: 'host' }
                  end
                }
              }
            }
          }
        end

        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :object,
                   properties: {
                     type: { type: :string },
                     id: ref_schema('uuid'),
                     attributes: ref_schema('profile'),
                     relationships: ref_schema('profile_relationships')
                   }
                 }
               }

        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end

    delete 'Destroy a profile' do
      tags 'profile'
      description 'Destroys a profile'
      operationId 'DestroyProfile'

      content_types
      auth_header

      parameter name: :id, in: :path, type: :string
      include_param

      response '404', 'profile not found' do
        let(:id) { 'invalid' }
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:include) { '' } # work around buggy rswag

        after { |e| autogenerate_examples(e) }

        run_test!
      end

      response '202', 'destroys a profile' do
        let(:'X-RH-IDENTITY') { encoded_header(@account) }
        let(:id) do
          FactoryBot.create(:profile, account: @account).id
        end
        let(:include) { '' } # work around buggy rswag

        schema type: :object,
               properties: {
                 meta: ref_schema('metadata'),
                 links: ref_schema('links'),
                 data: {
                   type: :object,
                   properties: {
                     type: { type: :string },
                     id: ref_schema('uuid'),
                     attributes: ref_schema('profile'),
                     relationships: ref_schema('profile_relationships')
                   }
                 }
               }

        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end
  end
end
