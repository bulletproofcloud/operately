defmodule OperatelyWeb.AccountOauthController do
  use OperatelyWeb, :controller
  require Logger

  alias Operately.Billing.EnforceLimits.LimitError
  alias Operately.People
  alias Operately.People.CliAuthSession
  alias Operately.InviteLinks
  alias Operately.Companies
  alias Operately.Oidc
  alias OperatelyWeb.AccountAuth
  alias OperatelyWeb.Paths

  plug :require_oidc_enabled when action in [:request, :callback]
  plug :store_redirect_in_state when action == :request
  plug Ueberauth

  @cli_auth_session_key :oauth_cli_auth_session_id

  @doc """
  Stores the redirect_to parameter in the session before initiating OAuth flow.
  This ensures we can redirect the user to the correct page after authentication.
  """
  def store_redirect_in_state(conn, _opts) do
    conn
    |> maybe_store_redirect(conn.params["redirect_to"])
    |> maybe_store_invite_token(conn.params["invite_token"])
  end

  def require_oidc_enabled(%{params: %{"provider" => "oidc"}} = conn, _opts) do
    cond do
      not Oidc.Config.enabled?() ->
        conn |> redirect(to: "/log_in?sso_error=not_configured") |> halt()

      Process.whereis(Oidc.Config.issuer()) == nil ->
        Logger.warning("OIDC provider configuration worker is not running")
        conn |> redirect(to: "/log_in?sso_error=failed") |> halt()

      true ->
        conn
    end
  end

  def require_oidc_enabled(conn, _opts), do: conn

  # Ueberauth redirects to the provider itself; this action runs only when the
  # strategy could not build that redirect (for example, no provider configuration).
  def request(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => "oidc"}) do
    Logger.warning("OIDC login request failed: #{inspect(Enum.map(failure.errors, &{&1.message_key, &1.message}))}")
    sso_error(conn, "failed")
  end

  @doc """
  Handles the callback from Google OAuth authentication.

  After successful authentication:
  1. Retrieves the redirect_to parameter from the session
  2. Creates or fetches the user account
  3. Logs in the user and redirects them to the appropriate page
  """
  def callback(
        %{assigns: %{ueberauth_auth: %{info: account_info}}} = conn,
        params = %{"provider" => "google"}
      ) do
    {conn, redirect_params} = get_and_clear_redirect_params(conn, params)
    {conn, invite_token} = get_and_clear_invite_token(conn, params)

    account_attrs = %{
      email: account_info.email,
      name: account_info.name,
      image: account_info.image
    }

    case People.find_or_create_account_with_source(account_attrs) do
      {:ok, account, account_source} ->
        {conn, cli_auth_session_id} = get_and_clear_cli_auth_session_id(conn, params)

        if cli_auth_session_id do
          complete_cli_auth_without_browser_login(conn, account, invite_token, cli_auth_session_id, redirect_params, account_source)
        else
          {redirect_params, conn} = maybe_handle_invite(conn, account, invite_token, redirect_params)

          params = Map.put(redirect_params, "remember_me", "true")
          AccountAuth.log_in_account(conn, account, params)
        end

      e ->
        Logger.error("Failed to fetch or create account: #{inspect(e)}")
        conn |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = auth}} = conn, %{"provider" => "oidc"} = params) do
    case Oidc.Identity.from_ueberauth(auth) do
      {:ok, identity} -> handle_oidc_identity(conn, identity, params)
      {:error, _} -> sso_error(conn, "failed")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => "oidc"}) do
    Logger.warning("OIDC callback failed: #{inspect(Enum.map(failure.errors, &{&1.message_key, &1.message}))}")
    sso_error(conn, "failed")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: "/")
  end

  defp handle_oidc_identity(conn, identity, params) do
    {conn, redirect_params} = get_and_clear_redirect_params(conn, params)
    {conn, invite_token} = get_and_clear_invite_token(conn, params)

    case Oidc.FetchOrLinkAccountOperation.call(identity, invite?: valid_invite?(invite_token, identity)) do
      {:ok, account, source} ->
        account_source = if source == :created, do: :created, else: :existing
        {conn, cli_auth_session_id} = get_and_clear_cli_auth_session_id(conn, params)

        if cli_auth_session_id do
          complete_cli_auth_without_browser_login(conn, account, invite_token, cli_auth_session_id, redirect_params, account_source)
        else
          {redirect_params, conn} = maybe_handle_invite(conn, account, invite_token, redirect_params)

          AccountAuth.log_in_account(
            conn,
            account,
            Map.put(redirect_params, "remember_me", "true"),
            id_token_session(identity.id_token)
          )
        end

      {:error, :email_not_verified} ->
        sso_error(conn, "email_not_verified")

      {:error, :no_account} ->
        sso_error(conn, "no_account")

      {:error, reason} ->
        Logger.error("OIDC login failed: #{inspect(reason)}")
        sso_error(conn, "failed")
    end
  end

  # Account creation is unlocked only by a usable company-wide invite link
  # (active, and the email domain is allowed). Personal links belong to an
  # existing person/account, so they never justify creating a new account.
  defp valid_invite?(nil, _identity), do: false

  defp valid_invite?(invite_token, identity) do
    with {:ok, link} <- InviteLinks.get_invite_link_by_token(invite_token),
         true <- link.type == :company_wide,
         {:ok, _} <- InviteLinks.validate_invite_link(link, %{email: identity.email}) do
      true
    else
      _ -> false
    end
  end

  # Passed to log_in_account, which stores it after renewing the session.
  # Tokens too large for the cookie are skipped (logout then stays local).
  @max_id_token_bytes 2048

  defp id_token_session(id_token) when is_binary(id_token) and byte_size(id_token) <= @max_id_token_bytes,
    do: %{oidc_id_token: id_token}

  defp id_token_session(_), do: %{}

  defp sso_error(conn, code), do: redirect(conn, to: "/log_in?sso_error=" <> code)

  defp get_and_clear_redirect_params(conn, params) do
    redirect_to = get_session(conn, :oauth_redirect_to)

    redirect_params =
      if redirect_to, do: Map.put(params, "redirect_to", redirect_to), else: params

    conn = delete_session(conn, :oauth_redirect_to)

    {conn, redirect_params}
  end

  defp get_and_clear_invite_token(conn, params) do
    invite_token = params["invite_token"] || get_session(conn, :oauth_invite_token)
    conn = delete_session(conn, :oauth_invite_token)

    {conn, normalize_invite_token(invite_token)}
  end

  defp get_and_clear_cli_auth_session_id(conn, params) do
    cli_auth_session_id = params["cli_auth_session_id"] || get_session(conn, @cli_auth_session_key)
    conn = delete_session(conn, @cli_auth_session_key)

    {conn, cli_auth_session_id}
  end

  defp maybe_store_redirect(conn, redirect_to) do
    case OperatelyWeb.Plugs.SsoOnlyLoginRedirect.safe_redirect_to(redirect_to) do
      nil -> conn
      path -> put_session(conn, :oauth_redirect_to, path)
    end
  end

  defp maybe_store_invite_token(conn, nil), do: conn
  defp maybe_store_invite_token(conn, ""), do: conn

  defp maybe_store_invite_token(conn, invite_token),
    do: put_session(conn, :oauth_invite_token, invite_token)

  defp maybe_handle_invite(conn, _account, nil, params), do: {params, conn}

  defp maybe_handle_invite(conn, account, invite_token, params) do
    case InviteLinks.join_company_via_invite_link(account, invite_token) do
      {:ok, person} ->
        company = Companies.get_company!(person.company_id)
        path = Paths.home_path(company)
        {Map.put(params, "redirect_to", path), conn}

      {:error, %LimitError{}} ->
        {Map.put(params, "redirect_to", Paths.invite_join_full_path(invite_token)), conn}

      {:error, _reason} ->
        {params, conn}
    end
  end

  defp maybe_complete_cli_auth(nil, _account, _account_source), do: :ok

  defp maybe_complete_cli_auth(cli_auth_session_id, account, account_source) do
    case CliAuthSession.get_by_id(cli_auth_session_id) do
      nil ->
        :ok

      session ->
        case CliAuthSession.complete_google_auth(session, account, account_source) do
          {:ok, _session} -> :ok
          {:error, _reason} -> :ok
        end
    end
  end

  defp complete_cli_auth_without_browser_login(conn, account, invite_token, cli_auth_session_id, redirect_params, account_source) do
    maybe_join_via_invite(account, invite_token)
    maybe_complete_cli_auth(cli_auth_session_id, account, account_source)

    redirect_to = redirect_params["redirect_to"] || Paths.cli_login_success_path(cli_auth_session_id)
    redirect(conn, to: redirect_to)
  end

  defp maybe_join_via_invite(_account, nil), do: :ok

  defp maybe_join_via_invite(account, invite_token) do
    case InviteLinks.join_company_via_invite_link(account, invite_token) do
      {:ok, _person} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp normalize_invite_token(nil), do: nil
  defp normalize_invite_token(""), do: nil
  defp normalize_invite_token(token), do: token

  if Application.compile_env(:operately, :test_routes) do
    def test_oidc(conn, params) do
      verify_application_env()

      identity = %Oidc.Identity{
        issuer: params["iss"],
        subject: params["sub"],
        email: params["email"],
        email_verified: params["email_verified"] in [true, "true"],
        name: params["name"],
        picture: params["picture"],
        id_token: params["id_token"]
      }

      handle_oidc_identity(conn, identity, params)
    end

    def test_google(conn, params) do
      verify_application_env()

      # Test-only shortcut for Google OAuth. We still complete the real CLI auth session below.
      {account, account_source} =
        cond do
          params["account_id"] ->
            {People.get_account!(params["account_id"]), :existing}

          params["email"] ->
            attrs = %{
              email: params["email"],
              name: params["name"] || params["email"],
              image: params["image"] || default_google_avatar()
            }

            case People.find_or_create_account_with_source(attrs) do
              {:ok, account, account_source} -> {account, account_source}
              {:error, reason} -> raise "Failed to create account: #{inspect(reason)}"
            end

          true ->
            raise "Missing account identifier"
        end

      {conn, redirect_params} = get_and_clear_redirect_params(conn, params)
      {conn, invite_token} = get_and_clear_invite_token(conn, params)
      {conn, cli_auth_session_id} = get_and_clear_cli_auth_session_id(conn, params)

      if cli_auth_session_id do
        complete_cli_auth_without_browser_login(conn, account, invite_token, cli_auth_session_id, redirect_params, account_source)
      else
        {redirect_params, conn} = maybe_handle_invite(conn, account, invite_token, redirect_params)
        params = Map.put(redirect_params, "remember_me", "true")

        AccountAuth.log_in_account(conn, account, params)
      end
    end

    defp verify_application_env() do
      if Application.get_env(:operately, :app_env) != :test do
        raise "You are trying to use the test Google auth route in a non-test environment."
      end
    end

    defp default_google_avatar() do
      "https://example.com/test-google-avatar.png"
    end
  end
end
