defmodule Operately.Oidc.ConfigTest do
  use ExUnit.Case, async: false

  alias Operately.Oidc.Config

  @keys [:oidc_issuer_url, :oidc_client_id, :allow_login_with_oidc, :allow_signup_with_oidc,
         :oidc_require_verified_email, :oidc_provider_name, :allow_login_with_email, :allow_login_with_google]

  setup do
    saved = Enum.map(@keys, &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, false)
    :ok
  end

  test "enabled? needs both the flag and an issuer" do
    assert Config.enabled?()

    Application.put_env(:operately, :oidc_issuer_url, nil)
    refute Config.enabled?()

    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_oidc, false)
    refute Config.enabled?()
  end

  test "sso_only? when OIDC is the only login method" do
    assert Config.sso_only?()

    Application.put_env(:operately, :allow_login_with_email, true)
    refute Config.sso_only?()

    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, true)
    refute Config.sso_only?()
  end

  test "provider_name defaults to SSO" do
    Application.put_env(:operately, :oidc_provider_name, nil)
    assert Config.provider_name() == "SSO"

    Application.put_env(:operately, :oidc_provider_name, "Authentik")
    assert Config.provider_name() == "Authentik"
  end

  test "require_verified_email? defaults to true" do
    Application.put_env(:operately, :oidc_require_verified_email, nil)
    assert Config.require_verified_email?()

    Application.put_env(:operately, :oidc_require_verified_email, false)
    refute Config.require_verified_email?()
  end

  test "signup_allowed? defaults to false" do
    Application.put_env(:operately, :allow_signup_with_oidc, nil)
    refute Config.signup_allowed?()
  end

  test "post_logout_redirect_uri points at /logged_out" do
    assert String.ends_with?(Config.post_logout_redirect_uri(), "/logged_out")
  end
end
