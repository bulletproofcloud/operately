defmodule OperatelyWeb.PageControllerTest do
  use OperatelyWeb.ConnCase

  import Operately.PeopleFixtures
  import Operately.CompaniesFixtures

  test "GET / renders configured false when there are no companies and no accounts", %{conn: conn} do
    conn = get(conn, "/")

    assert html_response(conn, 200)
    assert conn.resp_body =~ ~s("configured":false)
  end

  test "GET / renders configured true when there are accounts but no companies", %{conn: conn} do
    account_fixture()

    conn = get(conn, "/")

    assert html_response(conn, 200)
    assert conn.resp_body =~ ~s("configured":true)
  end

  test "GET / renders configured true when there is at least one company", %{conn: conn} do
    company_fixture()

    conn = get(conn, "/")

    assert html_response(conn, 200)
    assert conn.resp_body =~ ~s("configured":true)
  end

  describe "OIDC app config" do
    setup do
      keys = [:allow_login_with_oidc, :oidc_issuer_url, :allow_login_with_email, :allow_login_with_google, :oidc_provider_name]
      saved = Enum.map(keys, &{&1, Application.get_env(:operately, &1)})
      on_exit(fn -> Enum.each(saved, fn {k, v} -> Application.put_env(:operately, k, v) end) end)
      :ok
    end

    test "exposes OIDC flags", %{conn: conn} do
      Application.put_env(:operately, :allow_login_with_oidc, true)
      Application.put_env(:operately, :oidc_issuer_url, "https://idp.example.localhost/app/")
      Application.put_env(:operately, :allow_login_with_email, true)
      Application.put_env(:operately, :oidc_provider_name, "Authentik")

      html = conn |> get("/log_in") |> html_response(200)

      assert html =~ ~s("allowLoginWithOidc":true)
      assert html =~ ~s("oidcProviderName":"Authentik")
      assert html =~ ~s("ssoOnly":false)
    end
  end

  describe "vite_dev_url/0" do
    setup do
      original_dev_host = System.get_env("OPERATELY_DEV_HOST")
      original_port_offset = System.get_env("PORT_OFFSET")

      on_exit(fn ->
        restore_system_env("OPERATELY_DEV_HOST", original_dev_host)
        restore_system_env("PORT_OFFSET", original_port_offset)
      end)

      :ok
    end

    test "defaults to localhost on the default vite port" do
      System.delete_env("OPERATELY_DEV_HOST")
      System.delete_env("PORT_OFFSET")

      assert OperatelyWeb.PageController.vite_dev_url() == "http://localhost:4005"
    end

    test "uses OPERATELY_DEV_HOST when set" do
      System.put_env("OPERATELY_DEV_HOST", "100.64.0.5")
      System.delete_env("PORT_OFFSET")

      assert OperatelyWeb.PageController.vite_dev_url() == "http://100.64.0.5:4005"
    end

    test "respects PORT_OFFSET for the vite port" do
      System.put_env("OPERATELY_DEV_HOST", "devbox.lan")
      System.put_env("PORT_OFFSET", "4100")

      assert OperatelyWeb.PageController.vite_dev_url() == "http://devbox.lan:4105"
    end
  end

  defp restore_system_env(key, value) do
    case value do
      nil -> System.delete_env(key)
      value -> System.put_env(key, value)
    end
  end
end
