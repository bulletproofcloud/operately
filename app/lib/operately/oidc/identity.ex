defmodule Operately.Oidc.Identity do
  @moduledoc "The facts Operately uses from a validated OIDC login."

  defstruct [:issuer, :subject, :email, :email_verified, :name, :picture, :id_token]

  @type t :: %__MODULE__{}

  def from_ueberauth(%Ueberauth.Auth{} = auth) do
    raw = auth.extra && auth.extra.raw_info
    claims = Map.merge((raw && raw.claims) || %{}, (raw && raw.userinfo) || %{})

    identity = %__MODULE__{
      issuer: claims["iss"],
      subject: claims["sub"],
      email: claims["email"],
      email_verified: claims["email_verified"] in [true, "true"],
      name: claims["name"],
      picture: claims["picture"],
      id_token: auth.credentials && auth.credentials.other[:id_token]
    }

    if present?(identity.issuer) and present?(identity.subject) and present?(identity.email) do
      {:ok, identity}
    else
      {:error, :invalid_identity}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
