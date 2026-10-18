defmodule Operately.People.AccountIdentity do
  use Operately.Schema

  import Ecto.Query, only: [from: 2]

  alias Operately.Repo
  alias Operately.People.Account

  schema "account_identities" do
    belongs_to :account, Account

    field :provider, :string
    field :issuer, :string
    field :subject, :string

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:account_id, :provider, :issuer, :subject])
    |> validate_required([:account_id, :provider, :issuer, :subject])
    |> unique_constraint([:issuer, :subject])
    |> unique_constraint([:account_id, :provider, :issuer])
  end

  def link(%Account{} = account, issuer, subject) do
    %__MODULE__{}
    |> changeset(%{account_id: account.id, provider: "oidc", issuer: issuer, subject: subject})
    |> Repo.insert()
  end

  def get_account(issuer, subject) do
    Repo.one(
      from i in __MODULE__,
        join: a in Account,
        on: a.id == i.account_id,
        where: i.issuer == ^issuer and i.subject == ^subject and is_nil(a.deleted_at),
        select: a
    )
  end
end
