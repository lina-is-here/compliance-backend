# frozen_string_literal: true

require 'base64'

# Helpers to handle the b64 identity header.
class IdentityHeader
  CERT_AUTH = 'cert-auth'

  def initialize(b64_identity)
    @b64_identity = b64_identity
  end

  def blank?
    @b64_identity.blank?
  end

  def valid?
    identity.present? && entitled?
  end

  def content
    @content ||=
      begin
        JSON.parse(Base64.decode64(@b64_identity))
      rescue JSON::ParserError
        {}
      end
  end

  def identity
    content['identity']
  end

  # rubocop:disable Naming/PredicateName
  def is_internal
    identity&.dig('user', 'is_internal')
  end
  # rubocop:enable Naming/PredicateName

  def entitlements
    content['entitlements']
  end

  def entitled?
    entitlements&.dig('insights', 'is_entitled')
  end

  def auth_type
    identity&.dig('auth_type')
  end

  def cert_based?
    auth_type == CERT_AUTH
  end
end
