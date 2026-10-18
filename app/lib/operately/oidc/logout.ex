defmodule Operately.Oidc.Logout do
  @moduledoc "Where the browser goes after Operately clears its session."

  alias Operately.Oidc.Config

  def redirect_url(id_token) do
    cond do
      not Config.enabled?() -> nil
      is_binary(id_token) -> provider_logout_url(id_token) || "/logged_out"
      Config.sso_only?() -> "/logged_out"
      true -> nil
    end
  end

  defp provider_logout_url(id_token) do
    if Process.whereis(Config.issuer()) do
      case Oidcc.initiate_logout_url(id_token, Config.issuer(), Config.client_id(), %{post_logout_redirect_uri: Config.post_logout_redirect_uri()}) do
        {:ok, url} -> IO.iodata_to_binary(url)
        {:error, _} -> nil
      end
    end
  end
end
