defmodule Operately.People.AccountIdentityTest do
  use Operately.DataCase

  import Operately.PeopleFixtures

  alias Operately.People.AccountIdentity

  @iss "https://idp.example.localhost/app/"

  test "link then get_account by issuer and subject" do
    account = account_fixture()

    assert {:ok, _} = AccountIdentity.link(account, @iss, "sub-1")
    assert AccountIdentity.get_account(@iss, "sub-1").id == account.id
    assert AccountIdentity.get_account(@iss, "sub-2") == nil
    assert AccountIdentity.get_account("https://other.example/", "sub-1") == nil
  end

  test "an issuer and subject can only be linked once" do
    a = account_fixture()
    b = account_fixture()

    assert {:ok, _} = AccountIdentity.link(a, @iss, "sub-1")
    assert {:error, %Ecto.Changeset{}} = AccountIdentity.link(b, @iss, "sub-1")
  end

  test "an account has one identity per issuer" do
    account = account_fixture()

    assert {:ok, _} = AccountIdentity.link(account, @iss, "sub-1")
    assert {:error, %Ecto.Changeset{}} = AccountIdentity.link(account, @iss, "sub-2")
  end

  test "get_account ignores soft-deleted accounts" do
    account = account_fixture()
    {:ok, _} = AccountIdentity.link(account, @iss, "sub-1")

    account |> Ecto.Changeset.change(deleted_at: DateTime.utc_now()) |> Operately.Repo.update!()

    assert AccountIdentity.get_account(@iss, "sub-1") == nil
  end
end
