defmodule Operately.Features.OidcLoginTest do
  use Operately.FeatureCase

  import Operately.CompaniesFixtures
  import Operately.PeopleFixtures

  alias Operately.Mcp
  alias Operately.Oidc
  alias Operately.Support.Features.UI

  @moduletag :oidc_e2e

  @mcp_client %{
    client_id: "https://client.example.com/oauth/client.json",
    client_name: "Example MCP Client",
    redirect_uris: ["https://client.example.com/callback"],
    token_endpoint_auth_method: "none"
  }

  # The issuer worker loads the provider's discovery document after boot.
  setup_all do
    wait_for_provider_configuration(60)
    :ok
  end

  setup ctx do
    keys = [:allow_login_with_oidc, :allow_login_with_email, :allow_login_with_google, :allow_signup_with_oidc]
    saved = Enum.map(keys, &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :allow_login_with_email, false)
    Application.put_env(:operately, :allow_login_with_google, false)
    Application.put_env(:operately, :allow_signup_with_oidc, false)

    company = company_fixture(%{company_name: "E2E Company"})
    {:ok, Map.put(ctx, :company, company)}
  end

  feature "SSO-only: visiting the app logs an existing member straight in", ctx do
    person_fixture_with_account(%{company_id: ctx.company.id, email: "e2e@example.localhost", full_name: "E2E User"})

    ctx
    |> UI.visit("/")
    |> UI.assert_page(OperatelyWeb.Paths.home_path(ctx.company))
  end

  feature "SSO-only: no account is refused with a message", ctx do
    ctx
    |> UI.visit("/")
    |> UI.assert_text("No Operately account for this email. Ask an admin for an invite.")
  end

  feature "invite link creates and joins the account through the provider", ctx do
    creator = hd(Operately.People.list_people(ctx.company.id))
    {:ok, invite_link} = Operately.InviteLinks.create_invite_link(%{company_id: ctx.company.id, author_id: creator.id})

    ctx
    |> UI.visit("/join/#{invite_link.token}")
    |> UI.click(testid: "log-in-and-join")
    |> UI.assert_page(OperatelyWeb.Paths.home_path(ctx.company))

    assert {:ok, _account} = Operately.People.Account.get(:system, email: "e2e@example.localhost")
  end

  feature "logout lands on /logged_out and does not log straight back in", ctx do
    person_fixture_with_account(%{company_id: ctx.company.id, email: "e2e@example.localhost", full_name: "E2E User"})

    ctx
    |> UI.visit("/")
    |> UI.assert_page(OperatelyWeb.Paths.home_path(ctx.company))
    |> UI.visit("/account")
    |> UI.click(testid: "log-out-button")
    |> UI.assert_has(testid: "logged-out-page")
    |> UI.assert_page("/logged_out")
  end

  # The browser test above cannot tell a provider round-trip from the local
  # /logged_out fallback, so this proves the URL Operately hands the browser
  # points at the provider, then follows it in the browser.
  feature "logout goes through the provider's end_session endpoint and back", ctx do
    id_token = mock_provider_id_token()
    provider = Oidcc.ProviderConfiguration.Worker.get_provider_configuration(Oidc.Config.issuer())
    end_session_endpoint = provider.end_session_endpoint

    assert is_binary(end_session_endpoint)

    url = Oidc.Logout.redirect_url(id_token)

    assert String.starts_with?(url, end_session_endpoint)

    query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["id_token_hint"] == id_token
    assert query["post_logout_redirect_uri"] == Oidc.Config.post_logout_redirect_uri()

    ctx
    |> UI.visit(url)
    |> UI.assert_has(testid: "logged-out-page")
    |> UI.assert_page("/logged_out")
  end

  feature "a stale or replayed callback fails cleanly", ctx do
    person_fixture_with_account(%{company_id: ctx.company.id, email: "e2e@example.localhost", full_name: "E2E User"})

    ctx
    |> UI.visit("/")
    |> UI.assert_page(OperatelyWeb.Paths.home_path(ctx.company))
    |> UI.visit("/account")
    |> UI.click(testid: "log-out-button")
    |> UI.assert_has(testid: "logged-out-page")
    |> UI.visit("/accounts/auth/oidc/callback?code=replayed-code&state=not-issued-by-this-session")
    |> UI.assert_text("Sign-in failed. Please try again.")
    |> UI.assert_page("/log_in")
    |> UI.sleep(2000)
    |> UI.assert_page("/log_in")
    |> UI.assert_text("Sign-in failed. Please try again.")
  end

  feature "MCP authorize reaches the consent screen through the provider", ctx do
    previous_clients = Application.get_env(:operately, :mcp_oauth_clients)
    Application.put_env(:operately, :mcp_oauth_clients, [@mcp_client])
    on_exit(fn -> Application.put_env(:operately, :mcp_oauth_clients, previous_clients) end)

    person_fixture_with_account(%{company_id: ctx.company.id, email: "e2e@example.localhost", full_name: "E2E User"})

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => @mcp_client.client_id,
        "redirect_uri" => hd(@mcp_client.redirect_uris),
        "resource" => Mcp.canonical_resource_uri(),
        "scope" => "mcp:read",
        "state" => "mcp-state",
        "code_challenge" => OperatelyWeb.Mcp.ToolConnHelper.pkce_challenge(),
        "code_challenge_method" => "S256"
      })

    ctx
    |> UI.visit("/oauth/authorize?" <> query)
    |> UI.assert_text("Example MCP Client")
    |> UI.assert_text("E2E Company")
    |> UI.assert_page("/oauth/authorize")
  end

  defp wait_for_provider_configuration(0), do: flunk("the OIDC issuer worker never loaded the provider configuration")

  defp wait_for_provider_configuration(attempts) do
    case :oidcc_provider_configuration_worker.get_provider_configuration(Oidc.Config.issuer()) do
      :undefined ->
        Process.sleep(1000)
        wait_for_provider_configuration(attempts - 1)

      _configuration ->
        :ok
    end
  end

  # A real id_token from the mock provider, through the authorization code flow.
  defp mock_provider_id_token do
    issuer = Application.fetch_env!(:operately, :oidc_issuer_url)
    redirect_uri = "http://localhost/e2e-callback"

    authorize =
      Req.get!(issuer <> "/authorize",
        redirect: false,
        params: [
          client_id: Oidc.Config.client_id(),
          response_type: "code",
          redirect_uri: redirect_uri,
          scope: "openid email profile",
          state: "e2e-state",
          nonce: "e2e-nonce"
        ]
      )

    assert authorize.status == 302

    code =
      authorize
      |> Req.Response.get_header("location")
      |> hd()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("code")

    token =
      Req.post!(issuer <> "/token",
        form: [
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: Oidc.Config.client_id(),
          client_secret: "e2e-secret"
        ]
      )

    assert token.status == 200
    Map.fetch!(token.body, "id_token")
  end
end
