defmodule OperatelyWeb.Plugs.SsoOnlyLoginRedirect do
  @moduledoc """
  In SSO-only mode, a direct load of /log_in goes straight to the OIDC provider.
  Client-side navigations to /log_in are handled in the frontend.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/log_in"} = conn, _opts) do
    conn = fetch_query_params(conn)

    if Operately.Oidc.Config.sso_only?() and Operately.Setup.configured?() and is_nil(conn.assigns[:current_account]) and
         not Map.has_key?(conn.query_params, "sso_error") do
      query =
        [
          {"invite_token", conn.query_params["invite_token"]},
          {"redirect_to", safe_redirect_to(conn.query_params["redirect_to"])}
        ]
        |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
        |> URI.encode_query()

      path = if query == "", do: "/accounts/auth/oidc", else: "/accounts/auth/oidc?" <> query

      conn |> redirect(to: path) |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  def safe_redirect_to("/" <> rest = path) do
    cond do
      String.starts_with?(rest, "/") -> nil
      String.match?(path, ~r/[\x00-\x1f\x7f\\]/) -> nil
      true -> path
    end
  end

  def safe_redirect_to(_), do: nil
end
