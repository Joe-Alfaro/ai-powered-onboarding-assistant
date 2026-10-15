require "rails_helper"

# R19: the user is identified only from a Supabase JWT verified against the project's JWKS.
RSpec.describe Auth::JwtVerifier do
  subject(:verifier) { described_class.new(jwks_url: SupabaseTokens::JWKS_URL, issuer: SupabaseTokens::ISSUER) }

  let(:user_id) { SecureRandom.uuid }

  describe "R19: identifies the user from the verified token" do
    it "returns the token's sub as the user ID for an ES256 token" do
      identity = verifier.verify(supabase_token(sub: user_id, alg: "ES256"))

      expect(identity.user_id).to eq(user_id)
    end

    it "returns the token's sub as the user ID for an RS256 token" do
      identity = verifier.verify(supabase_token(sub: user_id, alg: "RS256"))

      expect(identity.user_id).to eq(user_id)
    end
  end

  describe "R19: rejects tokens that aren't verified Supabase tokens" do
    def expect_rejected(token)
      expect { verifier.verify(token) }.to raise_error(Auth::JwtVerifier::InvalidToken)
    end

    it "rejects an expired token" do
      expect_rejected(supabase_token(sub: user_id, claims: { exp: 1.hour.ago.to_i }))
    end

    it "rejects a token with no expiry" do
      expect_rejected(supabase_token(sub: user_id, drop: [ :exp ]))
    end

    it "rejects a token with no sub" do
      expect_rejected(supabase_token(sub: user_id, drop: [ :sub ]))
    end

    it "rejects a token signed by a key that isn't in the JWKS" do
      expect_rejected(supabase_token(sub: user_id, key: SupabaseTokens::ROGUE_EC_KEY, kid: "rogue"))
    end

    it "rejects a forged signature that reuses a published kid" do
      expect_rejected(supabase_token(sub: user_id, alg: "RS256", key: SupabaseTokens::ROGUE_RSA_KEY))
    end

    it "rejects an HS256 token, so a shared secret can't stand in for the JWKS key" do
      expect_rejected(supabase_token(sub: user_id, alg: "HS256", kid: SupabaseTokens::KIDS["RS256"]))
    end

    it "rejects an unsigned token (alg none)" do
      expect_rejected(supabase_token(sub: user_id, alg: "none", kid: SupabaseTokens::KIDS["ES256"]))
    end

    it "rejects a token from another issuer" do
      expect_rejected(supabase_token(sub: user_id, claims: { iss: "https://elsewhere.supabase.test/auth/v1" }))
    end

    it "rejects a token for another audience" do
      expect_rejected(supabase_token(sub: user_id, claims: { aud: "anon" }))
    end

    it "rejects a malformed token" do
      expect_rejected("not.a.jwt")
    end

    it "rejects a payload edited after signing" do
      header, _payload, signature = supabase_token(sub: user_id).split(".")
      tampered = Base64.urlsafe_encode64(JSON.generate(sub: SecureRandom.uuid, exp: 1.hour.from_now.to_i,
        aud: "authenticated", iss: SupabaseTokens::ISSUER), padding: false)

      expect_rejected([ header, tampered, signature ].join("."))
    end
  end

  describe "R19: admin role comes from app_metadata" do
    it "treats app_metadata.role admin as an admin" do
      expect(verifier.verify(supabase_token(sub: user_id, admin: true))).to be_admin
    end

    it "treats a token without the admin role as a non-admin" do
      expect(verifier.verify(supabase_token(sub: user_id))).not_to be_admin
    end

    it "ignores an admin role in user_metadata, which users can edit themselves" do
      token = supabase_token(sub: user_id, claims: { user_metadata: { role: "admin" } })

      expect(verifier.verify(token)).not_to be_admin
    end

    it "ignores a top-level role claim of admin" do
      expect(verifier.verify(supabase_token(sub: user_id, claims: { role: "admin" }))).not_to be_admin
    end
  end

  describe "JWKS fetching" do
    it "caches the JWKS instead of fetching it for every token" do
      3.times { verifier.verify(supabase_token(sub: user_id)) }

      expect(a_request(:get, SupabaseTokens::JWKS_URL)).to have_been_made.once
    end

    it "raises JwksUnavailable when the JWKS endpoint errors" do
      stub_request(:get, SupabaseTokens::JWKS_URL).to_return(status: 503)

      expect { verifier.verify(supabase_token(sub: user_id)) }.to raise_error(Auth::JwtVerifier::JwksUnavailable)
    end

    it "raises JwksUnavailable when the JWKS endpoint times out" do
      stub_request(:get, SupabaseTokens::JWKS_URL).to_timeout

      expect { verifier.verify(supabase_token(sub: user_id)) }.to raise_error(Auth::JwtVerifier::JwksUnavailable)
    end
  end
end
