# frozen_string_literal: true

require 'swagger_helper'

describe 'Benchmarks API' do
  path "#{Settings.path_prefix}/#{Settings.app_name}/benchmarks" do
    get 'List all benchmarks' do
      before { FactoryBot.create_list(:benchmark, 2) }

      tags 'benchmark'
      description 'Lists all benchmarks requested'
      operationId 'ListBenchmarks'

      content_types
      auth_header
      pagination_params
      search_params
      sort_params(Xccdf::Benchmark)

      include_param

      response '200', 'lists all benchmarks requested' do
        let(:'X-RH-IDENTITY') { encoded_header }
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
                       attributes: ref_schema('benchmark'),
                       relationships: ref_schema('benchmark_relationships')
                     }
                   }
                 }
               }

        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end
  end

  path "#{Settings.path_prefix}/#{Settings.app_name}/benchmarks/{id}" do
    get 'Retrieve a benchmark' do
      before do
        @profile = FactoryBot.create(:canonical_profile, :with_rules)
      end

      tags 'benchmark'
      description 'Retrieves data for a benchmark'
      operationId 'ShowBenchmark'

      content_types
      auth_header

      parameter name: :id, in: :path, type: :string
      include_param

      response '404', 'benchmark not found' do
        let(:id) { 'invalid' }
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:include) { '' } # work around buggy rswag

        after { |e| autogenerate_examples(e) }

        run_test!
      end

      response '200', 'retrieves a benchmark' do
        let(:'X-RH-IDENTITY') { encoded_header }
        let(:id) { @profile.benchmark.id }
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
                     attributes: ref_schema('benchmark'),
                     relationships: ref_schema('benchmark_relationships')
                   }
                 }
               }

        after { |e| autogenerate_examples(e) }

        run_test!
      end
    end
  end
end
