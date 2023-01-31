defmodule Hexdocs.Plug do
  use Plug.Builder
  use Plug.ErrorHandler
  use Hexdocs.Plug.Rollbax
  require Logger

  @key_html_fresh_time 60
  @key_asset_fresh_time 120
  @key_lifetime 60 * 60 * 24 * 29

  if Mix.env() == :dev do
    use Plug.Debugger, otp_app: :my_app
  end

  plug(Hexdocs.Plug.Status)
  plug(Hexdocs.Plug.Forwarded)
  plug(Plug.RequestId)

  plug(Plug.Static,
    at: "/",
    from: :hexdocs,
    gzip: true,
    only: ~w(css fonts images js),
    only_matching: ~w(favicon robots)
  )

  if Mix.env() != :test do
    plug(Logster.Plugs.Logger, excludes: [:params])
  end

  plug(Plug.Head)

  if Mix.env() == :prod do
    plug(Plug.SSL, rewrite_on: [:x_forwarded_proto])
  end

  # TODO: Use MFAs
  plug(Plug.Session,
    store: :cookie,
    key: "_hexdocs_key",
    signing_salt: {Application, :get_env, [:hexdocs, :session_signing_salt]},
    encryption_salt: {Application, :get_env, [:hexdocs, :session_encryption_salt]},
    max_age: 60 * 60 * 24 * 30
  )

  plug(:put_secret_key_base)
  plug(:fetch_session)
  plug(:fetch_query_params)
  plug(:run)

  defp put_secret_key_base(conn, _opts) do
    put_in(conn.secret_key_base, Application.get_env(:hexdocs, :session_key_base))
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
    case Hexdocs.Hexpm.verify_key(key, organization) do
      :ok ->
        conn
        |> put_session("key_refreshed_at", NaiveDateTime.utc_now())
        |> serve_page(organization)

      :refresh ->
        redirect_hexpm(conn, organization)

      {:error, message} ->
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: message))
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
    uri = rewrite_uri(conn)
    bucket_path = organization <> uri.path

    case fetch_page(bucket_path, uri.path) do
      {:ok, {200, headers, stream}} ->
        conn
        |> transfer_headers(headers)
        |> send_chunked(200)
        |> stream_body(stream)

      {:ok, {404, headers, _consumed_stream}} ->
        conn
        |> transfer_headers(headers)
        |> put_resp_content_type("text/html")
        |> send_resp(404, Hexdocs.Templates.not_found([]))

      {:redirect, path} ->
        redirect(conn, path)
    end
  end

  defp rewrite_uri(conn) do
    uri = URI.parse(conn.request_path)
    %URI{path: rewrite_path(uri.path)}
  end

  defp rewrite_path(nil) do
    nil
  end

  defp rewrite_path(path) do
    String.replace(path, ~r"^/([^/]*)/[^/]*/docs_config.js$", "/\\1/docs_config.js")
  end

  defp fetch_page(bucket_path, path) do
    if String.ends_with?(bucket_path, "/") do
      {:ok, stream_page(Path.join(bucket_path, "index.html"))}
    else
      case stream_page(bucket_path) do
        {404, headers, stream} ->
          # Read full body, since we don't use HTTP continuations
          Stream.run(stream)

          case head_page(Path.join(bucket_path, "index.html")) do
            {200, _headers} -> {:redirect, path <> "/"}
            _other -> {:ok, {404, headers, :stream_consumed}}
          end

        other ->
          {:ok, other}
      end
    end
  end

  defp stream_page(path) do
    Hexdocs.Store.stream_page(:docs_private_bucket, path)
  end

  defp head_page(path) do
    Hexdocs.Store.head_page(:docs_private_bucket, path)
  end

  defp stream_body(conn, stream) do
    Enum.reduce_while(stream, conn, fn
      {:ok, chunk}, conn ->
        case chunk(conn, chunk) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, reason} ->
            Logger.warning("Streaming sink error: #{inspect(reason)}")
            {:halt, conn}
        end

      {:error, reason}, conn ->
        # We stop streaming before sending the full body but cowboy
        # will clean up the connection for us
        Logger.warning("Streaming source error: #{inspect(reason)}")
        {:halt, conn}
    end)
  end

  @transfer_headers ~w(content-length content-type cache-control expires last-modified etag)

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
