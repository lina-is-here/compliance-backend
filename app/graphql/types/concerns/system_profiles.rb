# frozen_string_literal: true

module Types
  module Concerns
    # Methods related to system profiles and policies
    module SystemProfiles
      extend ActiveSupport::Concern

      def profiles(policy_id: nil)
        context_parent
        scope_profiles(object.all_profiles, policy_id)
      end

      def test_result_profiles(policy_id: nil)
        context_parent
        ::CollectionLoader.for(object.class, :test_result_profiles)
                          .load(object).then do |profiles|
          scope_profiles(profiles, policy_id)
        end
      end

      def policies(policy_id: nil)
        context_parent
        ::CollectionLoader.for(object.class, :assigned_internal_profiles)
                          .load(object).then do |profiles|
          scope_profiles(profiles, policy_id)
        end
      end

      private

      def scope_profiles(profiles, policy_id)
        policy_id ? profiles.in_policy(policy_id) : profiles
      end
    end
  end
end
