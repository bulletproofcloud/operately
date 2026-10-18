defmodule Operately.Oidc.FetchOrLinkAccountOperationTest do
  use Operately.DataCase

  import Operately.CompaniesFixtures
  import Operately.PeopleFixtures

  alias Operately.Oidc.{FetchOrLinkAccountOperation, Identity}
  alias Operately.People.AccountIdentity

  @iss "https://idp.example.localhost/app/"

  setup do
    saved = Enum.map([:allow_login_with_oidc, :oidc_issuer_url, :allow_signup_with_oidc, :oidc_require_verified_email],
      &{&1, Application.get_env(:operately, &1)})
    on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)

    Application.put_env(:operately, :allow_login_with_oidc, true)
    Application.put_env(:operately, :oidc_issuer_url, @iss)
    Application.put_env(:operately, :allow_signup_with_oidc, false)
    Application.put_env(:operately, :oidc_require_verified_email, true)
    :ok
  end

  defp identity(attrs) do
    struct!(%Identity{issuer: @iss, subject: "sub-1", email: "new@example.localhost", email_verified: true, name: "New Person"}, attrs)
  end

  test "step 1: a known identity logs into its account even after an email change" do
    account = account_fixture(%{email: "old@example.localhost"})
    {:ok, _} = AccountIdentity.link(account, @iss, "sub-1")

    assert {:ok, found, :existing} = FetchOrLinkAccountOperation.call(identity(email: "changed@example.localhost"), [])
    assert found.id == account.id
  end

  test "step 2: an existing account with the same email is linked" do
    account = account_fixture(%{email: "member@example.localhost"})

    assert {:ok, found, :linked} = FetchOrLinkAccountOperation.call(identity(email: "member@example.localhost"), [])
    assert found.id == account.id
    assert AccountIdentity.get_account(@iss, "sub-1").id == account.id
  end

  test "step 2: email matching ignores case" do
    account = account_fixture(%{email: "evangineer@example.localhost"})

    assert {:ok, found, :linked} = FetchOrLinkAccountOperation.call(identity(email: "Evangineer@Example.localhost"), [])
    assert found.id == account.id
  end

  test "step 3: an invite allows creating an account" do
    assert {:ok, account, :created} = FetchOrLinkAccountOperation.call(identity([]), invite?: true)
    assert account.email == "new@example.localhost"
    assert account.full_name == "New Person"
    assert AccountIdentity.get_account(@iss, "sub-1").id == account.id
  end

  test "step 3: signup allowed creates an account" do
    Application.put_env(:operately, :allow_signup_with_oidc, true)

    assert {:ok, _account, :created} = FetchOrLinkAccountOperation.call(identity([]), [])
  end

  test "step 4: no account, no invite, signup off is refused" do
    assert {:error, :no_account} = FetchOrLinkAccountOperation.call(identity([]), [])
    assert Operately.People.get_account_by_email("new@example.localhost") == nil
  end

  test "unverified email is refused before any lookup" do
    account_fixture(%{email: "member@example.localhost"})

    assert {:error, :email_not_verified} =
             FetchOrLinkAccountOperation.call(identity(email: "member@example.localhost", email_verified: false), [])

    assert AccountIdentity.get_account(@iss, "sub-1") == nil
  end

  test "unverified email is accepted when verification is not required" do
    Application.put_env(:operately, :oidc_require_verified_email, false)
    account_fixture(%{email: "member@example.localhost"})

    assert {:ok, _, :linked} = FetchOrLinkAccountOperation.call(identity(email: "member@example.localhost", email_verified: false), [])
  end

  test "a soft-deleted account is not logged into via its identity" do
    account = account_fixture(%{email: "gone@example.localhost"})
    {:ok, _} = AccountIdentity.link(account, @iss, "sub-1")
    account |> Ecto.Changeset.change(deleted_at: DateTime.utc_now()) |> Operately.Repo.update!()

    assert {:error, :no_account} = FetchOrLinkAccountOperation.call(identity(email: "gone@example.localhost"), [])
  end

  test "avatar is updated only when the provider sends a picture" do
    company = company_fixture()
    person = person_fixture_with_account(%{company_id: company.id, email: "pic@example.localhost", avatar_url: "https://old/a.png"})

    {:ok, _, :linked} = FetchOrLinkAccountOperation.call(identity(email: "pic@example.localhost", picture: nil), [])
    assert Operately.Repo.reload!(person).avatar_url == "https://old/a.png"

    {:ok, _, :existing} = FetchOrLinkAccountOperation.call(identity(email: "pic@example.localhost", picture: "https://new/b.png"), [])
    assert Operately.Repo.reload!(person).avatar_url == "https://new/b.png"
  end
end
