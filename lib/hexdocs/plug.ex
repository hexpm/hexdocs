defmodule HexDocs.Plug do
  use Plug.Builder

  @signing_salt Application.get_env(:hexdocs, :session_signing_salt)
  @encryption_salt Application.get_env(:hexdocs, :session_encryption_salt)
  @secret_key_base Application.get_env(:hexdocs, :session_key_base)
  @key_html_fresh_time 60
  @key_asset_fresh_time 120
  @key_lifetime 60 * 60 * 24 * 29

  # plug(Plug.RequestId)
  # plug(Plug.Logger)
  plug(Plug.Head)

  plug(Plug.Session,
    store: :cookie,
    key: "_hexdocs_key",
    signing_salt: @signing_salt,
    encryption_salt: @encryption_salt,
    max_age: 60 * 60 * 24 * 30
  )

  # TODO: SSL
  # TODO: Rollbar

  plug(:put_secret_key_base)
  plug(:fetch_session)
  plug(:fetch_query_params)
  plug(:run)

  defp put_secret_key_base(conn, _opts) do
    put_in(conn.secret_key_base, @secret_key_base)
  end

  defp run(conn, _opts) do
    subdomain = subdomain(conn.host)

    cond do
      !subdomain ->
        send_resp(conn, 400, "")

      key = conn.query_params["key"] ->
        update_key(conn, key)

      key = get_session(conn, "key") ->
        try_serve_page(conn, subdomain, key)

      true ->
        redirect_hexpm(conn, subdomain)
    end
  end

  defp try_serve_page(conn, organization, key) do
    created_at = get_session(conn, "key_created_at")
    refreshed_at = get_session(conn, "key_refreshed_at")

    if key_live?(created_at) do
      if key_fresh?(refreshed_at, conn.path_info) do
        serve_page(conn, organization)
      else
        serve_if_valid(conn, organization, key)
      end
    else
      redirect_hexpm(conn, organization)
    end
  end

  defp redirect_hexpm(conn, organization) do
    hexpm_url = Application.get_env(:hexdocs, :hexpm_url)
    url = "#{hexpm_url}/login?hexdocs=#{organization}&return=#{conn.request_path}"
    redirect(conn, url)
  end

  defp subdomain(host) do
    app_host = Application.get_env(:hexdocs, :host)

    case String.split(host, ".", parts: 2) do
      [subdomain, ^app_host] -> subdomain
      _ -> nil
    end
  end

  defp key_fresh?(timestamp, path_info) do
    file = List.last(path_info)
    lifetime = file_lifetime(file)
    NaiveDateTime.diff(NaiveDateTime.utc_now(), timestamp) <= lifetime
  end

  defp key_live?(timestamp) do
    NaiveDateTime.diff(NaiveDateTime.utc_now(), timestamp) <= @key_lifetime
  end

  defp serve_if_valid(conn, organization, key) do
    case HexDocs.Hexpm.verify_key(key, organization) do
      :ok ->
        conn
        |> put_session("key_refreshed_at", NaiveDateTime.utc_now())
        |> serve_page(organization)

      :refresh ->
        redirect_hexpm(conn, organization)

      {:error, message} ->
        # TODO: show error page 403.html?
        send_resp(conn, 403, "403 - #{message}")
    end
  end

  defp file_lifetime(file) do
    if Path.extname(file || "") in ["", ".html"] do
      @key_html_fresh_time
    else
      @key_asset_fresh_time
    end
  end

  defp update_key(conn, key) do
    now = NaiveDateTime.utc_now()

    params = Map.delete(conn.query_params, "key")
    path = conn.request_path <> Plug.Conn.Query.encode(params)

    conn
    |> put_session("key", key)
    |> put_session("key_refreshed_at", now)
    |> put_session("key_created_at", now)
    |> redirect(path)
  end

  defp serve_page(conn, organization) do
    uri = URI.parse(conn.request_path)
    bucket_path = organization <> uri.path

    case fetch_page(bucket_path, uri.path) do
      {:ok, {200, headers, body}} ->
        conn
        |> transfer_headers(headers)
        |> send_resp(200, body)

      {:ok, {404, headers, _body}} ->
        # TODO: 404 page
        conn
        |> transfer_headers(headers)
        |> send_resp(404, "404")

      {:redirect, path} ->
        redirect(conn, path)
    end
  end

  defp fetch_page(bucket_path, path) do
    case HexDocs.Store.get_page(:docs_bucket, bucket_path) do
      {404, headers, body} ->
        if String.ends_with?(bucket_path, "/") do
          {:ok, HexDocs.Store.get_page(:docs_bucket, Path.join(bucket_path, "index.html"))}
        else
          # TODO: head request
          case HexDocs.Store.get_page(:docs_bucket, Path.join(bucket_path, "index.html")) do
            {200, _headers, _body} -> {:redirect, path <> "/"}
            _other -> {:ok, {404, headers, body}}
          end
        end

      other ->
        {:ok, other}
    end
  end

  @transfer_headers ["content-type", "cache-control", "expires", "last-modified", "etag"]

  defp transfer_headers(conn, headers) do
    headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

    Enum.reduce(@transfer_headers, conn, fn header_name, conn ->
      case Map.fetch(headers, header_name) do
        {:ok, value} -> put_resp_header(conn, header_name, value)
        :error -> conn
      end
    end)
  end

  defp redirect(conn, url) do
    html = Plug.HTML.html_escape(url)
    body = "<html><body>You are being <a href=\"#{html}\">redirected</a>.</body></html>"

    conn
    |> put_resp_header("location", url)
    |> put_resp_header("content-type", "text/html")
    |> send_resp(302, body)
  end
end
