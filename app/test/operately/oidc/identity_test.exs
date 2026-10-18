defmodule Operately.Oidc.IdentityTest do
  use ExUnit.Case, async: true

  alias Operately.Oidc.Identity

  defp auth(claims, userinfo \\ nil, id_token \\ "id.token.value") do
    %Ueberauth.Auth{
      uid: claims["sub"],
      provider: :oidc,
      info: %Ueberauth.Auth.Info{email: claims["email"] || (userinfo || %{})["email"], name: claims["name"], image: claims["picture"]},
      credentials: %Ueberauth.Auth.Credentials{other: %{id_token: id_token}},
      extra: %Ueberauth.Auth.Extra{raw_info: %UeberauthOidcc.RawInfo{claims: claims, userinfo: userinfo}}
    }
  end

  @base %{"iss" => "https://idp/", "sub" => "abc", "email" => "a@example.localhost", "name" => "A", "email_verified" => true}

  test "builds an identity from claims" do
    assert {:ok, %Identity{issuer: "https://idp/", subject: "abc", email: "a@example.localhost", name: "A",
                           email_verified: true, picture: nil, id_token: "id.token.value"}} = Identity.from_ueberauth(auth(@base))
  end

  test "userinfo overrides claims" do
    {:ok, identity} = Identity.from_ueberauth(auth(Map.delete(@base, "email_verified"), %{"email_verified" => true, "picture" => "https://p/x.png"}))
    assert identity.email_verified
    assert identity.picture == "https://p/x.png"
  end

  test "userinfo cannot override the id_token issuer and subject" do
    {:ok, identity} = Identity.from_ueberauth(auth(@base, %{"iss" => "https://evil/", "sub" => "other"}))
    assert identity.issuer == "https://idp/"
    assert identity.subject == "abc"
  end

  test "email_verified is true only for true or \"true\"" do
    for {value, expected} <- [{true, true}, {"true", true}, {"false", false}, {nil, false}, {false, false}] do
      {:ok, identity} = Identity.from_ueberauth(auth(Map.put(@base, "email_verified", value)))
      assert identity.email_verified == expected, "#{inspect(value)}"
    end
  end

  test "missing issuer, subject or email is invalid" do
    for key <- ["iss", "sub", "email"] do
      assert {:error, :invalid_identity} = Identity.from_ueberauth(auth(Map.delete(@base, key)))
    end
  end
end
