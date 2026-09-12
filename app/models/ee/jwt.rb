module Ee
  class Jwt
    ALGORITHM   = "HS256"
    ISSUER      = "launchpad.enduranceevolution.com"
    COOKIE_NAME = :ee_jwt
    TTL         = 24.hours

    class << self
      def encode(identity:, app_keys:)
        now = Time.current
        payload = {
          sub:   identity.public_id,
          email: identity.email_address,
          name:  identity.user.name,
          apps:  app_keys,
          iat:   now.to_i,
          exp:   (now + TTL).to_i,
          iss:   ISSUER
        }
        ::JWT.encode(payload, secret, ALGORITHM)
      end

      def decode(token)
        return if token.blank?
        payload, _ = ::JWT.decode(token, secret, true,
          algorithm: ALGORITHM, iss: ISSUER, verify_iss: true)
        payload
      rescue ::JWT::DecodeError, ::JWT::ExpiredSignature
        nil
      end

      def cookie_domain = Rails.application.config.x.jwt_cookie_domain
      def secret        = Rails.application.credentials.ee_jwt_secret
    end
  end
end
