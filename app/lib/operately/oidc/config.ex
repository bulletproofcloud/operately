defmodule Operately.Oidc.Config do
  @moduledoc """
  Generic OIDC login settings, read from application env at call time.
  Set from environment variables in config/runtime.exs.
  """

  @issuer :operately_oidc

  def issuer, do: @issuer

  def enabled? do
    get(:allow_login_with_oidc, false) == true and present?(get(:oidc_issuer_url))
  end

  def signup_allowed?, do: enabled?() and get(:allow_signup_with_oidc, false) == true

  def require_verified_email?, do: get(:oidc_require_verified_email, true) != false

  def provider_name do
    case get(:oidc_provider_name) do
      name when is_binary(name) and name != "" -> name
      _ -> "SSO"
    end
  end

  def client_id, do: get(:oidc_client_id)

  def sso_only? do
    enabled?() and get(:allow_login_with_email, false) != true and get(:allow_login_with_google, false) != true
  end

  def post_logout_redirect_uri, do: OperatelyWeb.Endpoint.url() <> "/logged_out"

  defp get(key, default \\ nil), do: Application.get_env(:operately, key, default)

  defp present?(value), do: is_binary(value) and value != ""
end
