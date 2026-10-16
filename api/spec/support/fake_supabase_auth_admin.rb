# A stand-in for the Supabase Auth admin API's create-user endpoint, stubbed at the HTTP boundary.
# It remembers the users created, and answers a second create for the same email the way Supabase
# Auth does (422 email_exists), so a seed that isn't idempotent shows up as an error or a duplicate.
class FakeSupabaseAuthAdmin
  USERS_URL = "#{ENV.fetch("SUPABASE_URL")}/auth/v1/admin/users".freeze
  SERVICE_ROLE_KEY = ENV.fetch("SUPABASE_SERVICE_ROLE_KEY")

  # A created user, as the seed sent it.
  User = Data.define(:id, :email, :password, :email_confirm)

  attr_reader :users, :create_requests

  def initialize
    @users = []
    @create_requests = 0
  end

  def install
    WebMock.stub_request(:post, USERS_URL)
      .with(headers: { "Authorization" => "Bearer #{SERVICE_ROLE_KEY}", "apikey" => SERVICE_ROLE_KEY })
      .to_return { |request| create(JSON.parse(request.body)) }
    self
  end

  private
    def create(params)
      @create_requests += 1
      email = params["email"].to_s.downcase
      if users.any? { |user| user.email == email }
        return json(422, { code: 422, error_code: "email_exists",
                           msg: "A user with this email address has already been registered" })
      end

      user = User.new(id: SecureRandom.uuid, email: email, password: params["password"],
                      email_confirm: params["email_confirm"])
      users << user
      json(200, { id: user.id, email: user.email, aud: "authenticated", role: "authenticated" })
    end

    def json(status, body)
      { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
end
