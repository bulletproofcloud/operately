defmodule Operately.Oidc.FetchOrLinkAccountOperation do
  @moduledoc """
  Finds, links or creates the account for a validated OIDC identity.

  1. A known (issuer, subject) identity logs into its account.
  2. Otherwise an account with the same email is linked.
  3. Otherwise an invite, or allowed signup, creates the account.
  4. Otherwise the login is refused.
  """

  alias Operately.Repo
  alias Operately.Oidc.{Config, Identity}
  alias Operately.People.{Account, AccountIdentity}

  def call(%Identity{} = identity, opts) do
    with :ok <- check_email_verified(identity) do
      case AccountIdentity.get_account(identity.issuer, identity.subject) do
        %Account{} = account -> finish(account, identity, :existing)
        nil -> link_or_create(identity, Keyword.get(opts, :invite?, false))
      end
    end
  end

  defp check_email_verified(identity) do
    if Config.require_verified_email?() and not identity.email_verified, do: {:error, :email_not_verified}, else: :ok
  end

  defp link_or_create(identity, invite?) do
    case Account.get(:system, email: identity.email) do
      {:ok, account} ->
        with {:ok, _} <- AccountIdentity.link(account, identity.issuer, identity.subject), do: finish(account, identity, :linked)

      {:error, _} ->
        if invite? or Config.signup_allowed?(), do: create(identity), else: {:error, :no_account}
    end
  end

  defp create(identity) do
    Repo.transaction(fn ->
      with {:ok, account} <- Account.create(identity.name || identity.email, identity.email, random_password()),
           {:ok, _} <- AccountIdentity.link(account, identity.issuer, identity.subject) do
        account
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, account} -> finish(account, identity, :created)
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish(account, identity, source) do
    with :ok <- maybe_update_avatar(account, identity.picture), do: {:ok, account, source}
  end

  defp maybe_update_avatar(_account, nil), do: :ok

  defp maybe_update_avatar(account, picture) do
    account
    |> Repo.preload(:people)
    |> Map.fetch!(:people)
    |> Enum.reject(&(&1.avatar_blob_id || &1.avatar_url == picture))
    |> Enum.reduce_while(:ok, fn person, :ok ->
      case Operately.People.update_person(person, %{avatar_url: picture}) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp random_password, do: :crypto.strong_rand_bytes(32) |> Base.encode64()
end
