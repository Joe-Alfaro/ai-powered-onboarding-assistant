# Signs Supabase-style access tokens with test keys and serves them from a stubbed JWKS endpoint.
# Built on OpenSSL directly so the specs don't pick the app's JWT library.
module SupabaseTokens
  SUPABASE_URL = ENV.fetch("SUPABASE_URL")
  ISSUER = "#{SUPABASE_URL}/auth/v1".freeze
  JWKS_URL = ENV.fetch("SUPABASE_JWKS_URL")

  RSA_KEY = OpenSSL::PKey::RSA.generate(2048)
  EC_KEY = OpenSSL::PKey::EC.generate("prime256v1")
  # Never published in the JWKS: tokens signed with these must be rejected.
  ROGUE_RSA_KEY = OpenSSL::PKey::RSA.generate(2048)
  ROGUE_EC_KEY = OpenSSL::PKey::EC.generate("prime256v1")

  KIDS = { "RS256" => "spec-rsa", "ES256" => "spec-ec" }.freeze

  module_function

  def jwks
    { keys: [ rsa_jwk(RSA_KEY.public_key, KIDS["RS256"]), ec_jwk(EC_KEY, KIDS["ES256"]) ] }
  end

  def stub_jwks
    WebMock.stub_request(:get, JWKS_URL)
      .to_return(status: 200, body: JSON.generate(jwks), headers: { "Content-Type" => "application/json" })
  end

  # Claims follow a Supabase Auth access token. Pass `claims:` to override or add any of them,
  # and `drop:` to remove some.
  def supabase_token(sub:, alg: "ES256", key: nil, kid: KIDS[alg], admin: false, claims: {}, drop: [])
    now = Time.now.to_i
    payload = {
      iss: ISSUER,
      aud: "authenticated",
      sub: sub,
      role: "authenticated",
      email: "#{sub}@example.test",
      iat: now,
      exp: now + 3600,
      app_metadata: admin ? { provider: "email", role: "admin" } : { provider: "email" },
      user_metadata: {}
    }.merge(claims).except(*drop)
    header = { alg: alg, typ: "JWT" }
    header[:kid] = kid if kid
    sign(header, payload, alg, key || default_key(alg))
  end

  def auth_headers(sub, **)
    { "Authorization" => "Bearer #{supabase_token(sub: sub, **)}" }
  end

  def sign(header, payload, alg, key)
    input = "#{segment(JSON.generate(header))}.#{segment(JSON.generate(payload))}"
    signature =
      case alg
      when "RS256" then key.sign("SHA256", input)
      when "ES256" then der_to_raw(key.sign("SHA256", input))
      when "HS256" then OpenSSL::HMAC.digest("SHA256", key, input)
      when "none" then ""
      end
    "#{input}.#{segment(signature)}"
  end

  def default_key(alg)
    { "RS256" => RSA_KEY, "ES256" => EC_KEY, "HS256" => "not-the-jwks-key", "none" => nil }.fetch(alg)
  end

  def segment(bytes)
    Base64.urlsafe_encode64(bytes, padding: false)
  end

  def rsa_jwk(key, kid)
    { kty: "RSA", kid: kid, alg: "RS256", use: "sig", n: segment(key.n.to_s(2)), e: segment(key.e.to_s(2)) }
  end

  def ec_jwk(key, kid)
    point = key.public_key.to_bn.to_s(2) # 0x04 || x || y
    { kty: "EC", kid: kid, alg: "ES256", use: "sig", crv: "P-256", x: segment(point[1, 32]), y: segment(point[33, 32]) }
  end

  # ES256 signatures are the raw 64-byte r || s, not OpenSSL's DER encoding.
  def der_to_raw(der)
    OpenSSL::ASN1.decode(der).value.map { |int| int.value.to_s(2).rjust(32, "\x00") }.join
  end
end

RSpec.configure do |config|
  config.include SupabaseTokens
  config.before { SupabaseTokens.stub_jwks }
end
