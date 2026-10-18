defmodule OperatelyWeb.CliLoginControllerOidcTest do
  use OperatelyWeb.ConnCase, async: false

  alias Operately.People.CliAuthSession

  setup do
    keys = [:allow_login_with_oidc, :oidc_issuer_url, :allow_login_with_google]
    saved = Enum.map(keys, &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_google, false)

    {:ok, session, _raw} = CliAuthSession.create_pending_google_session(:login)
    {:ok, session: session}
  end

  test "browser login goes to the OIDC provider when it is the only SSO method", ctx do
    conn = build_conn() |> init_test_session(%{}) |> get("/cli-login/#{ctx.session.id}")

    assert redirected_to(conn) =~ ~r{^/accounts/auth/oidc\?}
  end

  test "Google stays the default when both are enabled", ctx do
    Application.put_env(:operately, :allow_login_with_google, true)

    conn = build_conn() |> init_test_session(%{}) |> get("/cli-login/#{ctx.session.id}")

    assert redirected_to(conn) =~ ~r{^/accounts/auth/google\?}
  end

  test "the provider parameter selects OIDC", ctx do
    Application.put_env(:operately, :allow_login_with_google, true)

    conn = build_conn() |> init_test_session(%{}) |> get("/cli-login/#{ctx.session.id}?provider=oidc")

    assert redirected_to(conn) =~ ~r{^/accounts/auth/oidc\?}
  end

  test "an OIDC login completes the pending CLI session", ctx do
    account = Operately.PeopleFixtures.account_fixture(%{email: "cli@example.localhost"})

    conn =
      build_conn()
      |> init_test_session(%{oauth_cli_auth_session_id: ctx.session.id})
      |> get("/accounts/auth/test_oidc", %{"iss" => "https://idp.example.localhost/app/", "sub" => "cli-sub", "email" => "cli@example.localhost", "email_verified" => "true"})

    assert conn.status == 302
    assert CliAuthSession.get_by_id(ctx.session.id).account_id == account.id
  end
end
