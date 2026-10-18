defmodule Operately.Features.LoginTest do
  use Operately.FeatureCase

  import Operately.CompaniesFixtures
  import Operately.PeopleFixtures

  alias Operately.Support.Features.UI

  @google_sign_in_query Query.css("[data-test-id=sign-in-with-google]")

  @oidc_sign_in_query Query.css("[data-test-id=sign-in-with-oidc]")

  setup ctx do
    company = company_fixture()
    person_fixture_with_account(%{company_id: company.id, full_name: "John Admin"})

    {:ok, ctx}
  end

  feature "Sign in with Google hidden", ctx do
    Application.put_env(:operately, :allow_login_with_google, false)

    ctx
    |> UI.visit("/")
    |> UI.assert_page("/log_in")
    |> UI.refute_has(@google_sign_in_query)
  end

  feature "Sign in with Google visible", ctx do
    Application.put_env(:operately, :allow_login_with_google, true)

    ctx
    |> UI.visit("/")
    |> UI.assert_page("/log_in")
    |> UI.assert_has(@google_sign_in_query)
  end

  feature "Sign in with OIDC visible next to email login", ctx do
    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :oidc_provider_name, "Authentik")
    Application.put_env(:operately, :allow_login_with_email, true)
    on_exit(fn -> Application.put_env(:operately, :allow_login_with_oidc, false) end)

    ctx
    |> UI.visit("/")
    |> UI.assert_page("/log_in")
    |> UI.assert_has(@oidc_sign_in_query)
    |> UI.assert_text("Sign in with Authentik")
  end

  feature "SSO error is shown and the button offered", ctx do
    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, false)
    on_exit(fn ->
      Application.put_env(:operately, :allow_login_with_oidc, false)
      Application.put_env(:operately, :allow_login_with_email, true)
    end)

    ctx
    |> UI.visit("/log_in?sso_error=no_account")
    |> UI.assert_text("No Operately account for this email. Ask an admin for an invite.")
    |> UI.assert_has(@oidc_sign_in_query)
  end
end
