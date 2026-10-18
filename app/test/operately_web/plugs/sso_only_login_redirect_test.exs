defmodule OperatelyWeb.Plugs.SsoOnlyLoginRedirectTest do
  use OperatelyWeb.ConnCase, async: false

  alias OperatelyWeb.Plugs.SsoOnlyLoginRedirect

  setup ctx do
    keys = [:allow_login_with_oidc, :oidc_issuer_url, :allow_login_with_email, :allow_login_with_google]
    saved = Enum.map(keys, &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, false)

    # Setup.configured? needs a company; before setup the plug must stay out of the way.
    unless ctx[:unconfigured], do: Operately.CompaniesFixtures.company_fixture()
    :ok
  end

  test "GET /log_in goes to the provider, carrying redirect_to and invite_token" do
    conn = get(build_conn(), "/log_in", %{"redirect_to" => "/c/goals", "invite_token" => "tok"})

    assert redirected_to(conn) == "/accounts/auth/oidc?invite_token=tok&redirect_to=%2Fc%2Fgoals"
  end

  test "no redirect when sso_error is present" do
    conn = get(build_conn(), "/log_in", %{"sso_error" => "no_account"})

    assert conn.status == 200
  end

  test "no redirect when another login method is enabled" do
    Application.put_env(:operately, :allow_login_with_email, true)

    assert get(build_conn(), "/log_in").status == 200
  end

  test "redirect_to that is not a same-site path is dropped" do
    for bad <- ["https://evil.example/", "//evil.example/", "evil"] do
      conn = get(build_conn(), "/log_in", %{"redirect_to" => bad})
      assert redirected_to(conn) == "/accounts/auth/oidc"
    end
  end

  test "no redirect for an already logged-in account" do
    account = Operately.PeopleFixtures.account_fixture()
    conn = build_conn() |> log_in_account(account) |> get("/log_in")

    refute conn.status == 302 and redirected_to(conn) =~ "/accounts/auth/oidc"
  end

  @tag :unconfigured
  test "no redirect before the instance is set up" do
    refute Operately.Setup.configured?()
    assert get(build_conn(), "/log_in").status == 200
  end

  test "safe_redirect_to" do
    assert SsoOnlyLoginRedirect.safe_redirect_to("/a/b") == "/a/b"
    assert SsoOnlyLoginRedirect.safe_redirect_to("//x") == nil
    assert SsoOnlyLoginRedirect.safe_redirect_to(nil) == nil
  end
end
