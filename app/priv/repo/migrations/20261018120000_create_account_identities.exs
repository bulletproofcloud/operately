defmodule Operately.Repo.Migrations.CreateAccountIdentities do
  use Ecto.Migration

  def change do
    create table(:account_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id), null: false
      add :provider, :string, null: false
      add :issuer, :string, null: false
      add :subject, :string, null: false

      timestamps()
    end

    create unique_index(:account_identities, [:issuer, :subject])
    create unique_index(:account_identities, [:account_id, :provider, :issuer])
  end
end
