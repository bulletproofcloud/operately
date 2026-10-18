defmodule Operately.Oidc.LogoutTest do
  use ExUnit.Case, async: false

  alias Operately.Oidc.Logout

  setup do
    keys = [:allow_login_with_oidc, :oidc_issuer_url, :allow_login_with_email, :allow_login_with_google]
    saved = Enum.map(keys, &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)
    :ok
  end

  test "nil when OIDC is off" do
    Application.put_env(:operately, :allow_login_with_oidc, false)
    assert Logout.redirect_url("tok") == nil
  end

  test "/logged_out in SSO-only mode without an id_token (remember-me session)" do
    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, false)

    assert Logout.redirect_url(nil) == "/logged_out"
  end

  test "/logged_out when the provider has no running configuration worker" do
    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")

    assert Logout.redirect_url("tok") == "/logged_out"
  end
end
