defmodule OperatelyWeb.EndpointForwardedHeadersTest do
  # Behind a TLS-terminating proxy, the URL the app sees for a request must be
  # the public https URL. ueberauth_oidcc compares Plug.Conn.request_url/1 of the
  # callback with the configured redirect_uri ("https://<OPERATELY_HOST>/accounts/auth/oidc/callback").
  use OperatelyWeb.ConnCase, async: false

  @callback_path "/accounts/auth/oidc/callback"
  @public_callback_url "https://operately.example.com/accounts/auth/oidc/callback"

  test "x-forwarded-proto https makes the request an https request", %{conn: conn} do
    conn =
      %{conn | host: "operately.example.com", port: 80}
      |> put_req_header("x-forwarded-proto", "https")
      |> get(@callback_path)

    assert conn.scheme == :https
    assert request_url(%{conn | query_string: ""}) == @public_callback_url
  end

  test "x-forwarded-port replaces the app's listen port", %{conn: conn} do
    conn =
      %{conn | host: "operately.example.com", port: 4000}
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-port", "443")
      |> get(@callback_path)

    assert conn.scheme == :https
    assert request_url(%{conn | query_string: ""}) == @public_callback_url
  end

  test "without forwarded headers the request is left as it arrived", %{conn: conn} do
    conn = %{conn | host: "operately.example.com", port: 4000} |> get(@callback_path)

    assert conn.scheme == :http
    assert request_url(%{conn | query_string: ""}) == "http://operately.example.com:4000" <> @callback_path
  end

  test "x-forwarded-host is not trusted", %{conn: conn} do
    conn =
      %{conn | host: "operately.example.com", port: 80}
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "evil.example.com")
      |> get(@callback_path)

    assert conn.host == "operately.example.com"
  end
end
