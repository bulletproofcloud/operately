defmodule OperatelyWeb.AccountOauthOidcTest do
  use OperatelyWeb.ConnCase, async: false

  import Operately.CompaniesFixtures
  import Operately.PeopleFixtures

  alias Operately.People.AccountIdentity

  @iss "https://idp.example.localhost/app/"

  setup do
    saved = Enum.map([:allow_login_with_oidc, :oidc_issuer_url, :allow_signup_with_oidc, :oidc_require_verified_email],
      &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, @iss)
    Application.put_env(:operately, :allow_signup_with_oidc, false)
    Application.put_env(:operately, :oidc_require_verified_email, true)

    conn =
      build_conn()
      |> Map.replace!(:secret_key_base, OperatelyWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    {:ok, conn: conn, company: company_fixture(%{name: "Test Company"})}
  end

  defp login(conn, params) do
    defaults = %{"iss" => @iss, "sub" => "sub-1", "email_verified" => "true", "id_token" => "header.payload.sig"}
    get(conn, "/accounts/auth/test_oidc", Map.merge(defaults, params))
  end

  test "existing account is linked, logged in and the id_token kept", ctx do
    account = account_fixture(%{email: "member@example.localhost"})

    conn = login(ctx.conn, %{"email" => "member@example.localhost"})

    assert conn.status == 302
    assert get_session(conn, :account_token)
    assert get_session(conn, :oidc_id_token) == "header.payload.sig"
    assert AccountIdentity.get_account(@iss, "sub-1").id == account.id
  end

  test "no account and signup off redirects with no_account", ctx do
    conn = login(ctx.conn, %{"email" => "stranger@example.localhost"})

    assert redirected_to(conn) == "/log_in?sso_error=no_account"
    refute get_session(conn, :account_token)
  end

  test "unverified email redirects with email_not_verified", ctx do
    account_fixture(%{email: "member@example.localhost"})

    conn = login(ctx.conn, %{"email" => "member@example.localhost", "email_verified" => "false"})

    assert redirected_to(conn) == "/log_in?sso_error=email_not_verified"
  end

  test "invite link creates the account and joins the company", ctx do
    {:ok, invite_link} =
      Operately.InviteLinks.create_invite_link(%{company_id: ctx.company.id, author_id: hd(Operately.People.list_people(ctx.company.id)).id})

    conn = login(ctx.conn, %{"email" => "invitee@example.localhost", "name" => "Invitee", "invite_token" => invite_link.token})

    assert conn.status == 302
    assert redirected_to(conn) == OperatelyWeb.Paths.home_path(ctx.company)
    assert Operately.People.get_account_by_email("invitee@example.localhost")
  end

  test "an unknown invite token does not bypass signup being off", ctx do
    conn = login(ctx.conn, %{"email" => "sneaky@example.localhost", "name" => "Sneaky", "invite_token" => "bogus-token"})

    assert redirected_to(conn) == "/log_in?sso_error=no_account"
    refute get_session(conn, :account_token)
    refute Operately.People.get_account_by_email("sneaky@example.localhost")
  end

  test "request phase when OIDC is not configured redirects with not_configured", ctx do
    Application.put_env(:operately, :allow_login_with_oidc, false)

    conn = get(ctx.conn, "/accounts/auth/oidc")

    assert redirected_to(conn) == "/log_in?sso_error=not_configured"
  end

  test "a callback without a valid OIDC result redirects with failed, never a 500", ctx do
    conn = get(ctx.conn, "/accounts/auth/oidc/callback", %{"state" => "stale", "code" => "replayed"})

    assert redirected_to(conn) == "/log_in?sso_error=failed"
  end
end
