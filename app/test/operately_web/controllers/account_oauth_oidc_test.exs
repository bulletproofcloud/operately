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

  describe "error redirects keep the invite context" do
    defp error_query(conn) do
      uri = URI.parse(redirected_to(conn))
      assert uri.path == "/log_in"
      URI.decode_query(uri.query)
    end

    defp with_context(conn, session) do
      Plug.Test.init_test_session(conn, session)
    end

    test "email_not_verified carries the session invite_token and redirect_to", ctx do
      account_fixture(%{email: "member@example.localhost"})
      conn = with_context(ctx.conn, %{oauth_invite_token: "tok-1", oauth_redirect_to: "/c/goals"})

      conn = login(conn, %{"email" => "member@example.localhost", "email_verified" => "false"})

      assert error_query(conn) == %{"sso_error" => "email_not_verified", "invite_token" => "tok-1", "redirect_to" => "/c/goals"}
      assert String.starts_with?(redirected_to(conn), "/log_in?sso_error=email_not_verified&")
    end

    test "no_account carries the invite_token param and stored redirect_to", ctx do
      conn = with_context(ctx.conn, %{oauth_redirect_to: "/c/goals"})

      conn = login(conn, %{"email" => "stranger@example.localhost", "invite_token" => "tok-2"})

      assert error_query(conn) == %{"sso_error" => "no_account", "invite_token" => "tok-2", "redirect_to" => "/c/goals"}
    end

    test "an unsafe stored redirect_to is not echoed", ctx do
      conn = with_context(ctx.conn, %{oauth_invite_token: "tok-3", oauth_redirect_to: "//evil.example"})

      conn = login(conn, %{"email" => "stranger@example.localhost"})

      assert error_query(conn) == %{"sso_error" => "no_account", "invite_token" => "tok-3"}
    end

    test "nothing stored gives exactly the bare error URL", ctx do
      conn = login(ctx.conn, %{"email" => "stranger@example.localhost"})
      assert redirected_to(conn) == "/log_in?sso_error=no_account"

      conn = login(ctx.conn, %{"email" => "stranger@example.localhost", "email_verified" => "false"})
      refute redirected_to(conn) =~ "redirect_to"
      refute redirected_to(conn) =~ "invite_token"
    end

    test "an empty invite_token is dropped", ctx do
      conn = login(ctx.conn, %{"email" => "stranger@example.localhost", "invite_token" => ""})
      assert redirected_to(conn) == "/log_in?sso_error=no_account"
    end
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

  test "an external redirect_to is not stored during the request phase", ctx do
    for bad <- ["https://evil.example/", "//evil.example/"] do
      conn = get(ctx.conn, "/accounts/auth/google", %{"redirect_to" => bad})
      assert get_session(conn, :oauth_redirect_to) == nil
    end
  end
end
