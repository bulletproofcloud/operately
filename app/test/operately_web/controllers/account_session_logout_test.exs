defmodule OperatelyWeb.AccountSessionLogoutTest do
  use OperatelyWeb.ConnCase, async: false

  import Operately.PeopleFixtures

  setup do
    saved = Application.get_env(:operately, :allow_login_with_oidc)
    on_exit(fn -> Application.put_env(:operately, :allow_login_with_oidc, saved) end)
    Application.put_env(:operately, :allow_login_with_oidc, false)
    :ok
  end

  test "logout answers JSON with a null redirect_url when OIDC is off" do
    account = account_fixture()
    conn = build_conn() |> log_in_account(account) |> delete("/accounts/log_out")

    assert json_response(conn, 200) == %{"redirect_url" => nil}
  end
end
