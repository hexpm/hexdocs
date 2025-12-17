defmodule Hexdocs.Plug do
  use Plug.Builder
  use Plug.ErrorHandler
  require Logger

  # OAuth token refresh buffer - refresh token 5 minutes before expiry
  @token_refresh_buffer 5 * 60

  use Sentry.PlugCapture

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

  plug(Sentry.PlugContext)

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
    max_age: 60 * 60 * 24 * 30,
    secure: Mix.env() == :prod,
    http_only: true,
    same_site: "Lax"
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

      # OAuth callback - exchange code for tokens
      conn.request_path == "/oauth/callback" ->
        handle_oauth_callback(conn, subdomain)

      # OAuth access token in session
      access_token = get_session(conn, "access_token") ->
        try_serve_page_oauth(conn, subdomain, access_token)

      true ->
        redirect_oauth(conn, subdomain)
    end
  end

  defp redirect_oauth(conn, organization) do
    code_verifier = Hexdocs.OAuth.generate_code_verifier()
    code_challenge = Hexdocs.OAuth.generate_code_challenge(code_verifier)
    state = Hexdocs.OAuth.generate_state()

    redirect_uri = build_oauth_redirect_uri(conn, organization)

    url =
      Hexdocs.OAuth.authorization_url(
        hexpm_url: Application.get_env(:hexdocs, :hexpm_url),
        client_id: Application.get_env(:hexdocs, :oauth_client_id),
        redirect_uri: redirect_uri,
        scope: "docs:#{organization}",
        state: state,
        code_challenge: code_challenge
      )

    conn
    |> put_session("oauth_code_verifier", code_verifier)
    |> put_session("oauth_state", state)
    |> put_session("oauth_return_path", conn.request_path)
    |> redirect(url)
  end

  defp build_oauth_redirect_uri(_conn, organization) do
    scheme = if Mix.env() == :prod, do: "https", else: "http"
    host = Application.get_env(:hexdocs, :host)
    "#{scheme}://#{organization}.#{host}/oauth/callback"
  end

  defp handle_oauth_callback(conn, organization) do
    code = conn.query_params["code"]
    state = conn.query_params["state"]
    error = conn.query_params["error"]
    stored_state = get_session(conn, "oauth_state")
    code_verifier = get_session(conn, "oauth_code_verifier")
    return_path = get_session(conn, "oauth_return_path") || "/"

    cond do
      error ->
        # User denied authorization or other OAuth error
        error_description = conn.query_params["error_description"] || error
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: error_description))

      is_nil(state) or state != stored_state ->
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: "Invalid OAuth state"))

      is_nil(code) ->
        send_resp(conn, 400, Hexdocs.Templates.auth_error(reason: "Missing authorization code"))

      true ->
        exchange_oauth_code(conn, code, code_verifier, organization, return_path)
    end
  end

  defp exchange_oauth_code(conn, code, code_verifier, organization, return_path) do
    redirect_uri = build_oauth_redirect_uri(conn, organization)

    opts =
      Hexdocs.OAuth.config()
      |> Keyword.put(:redirect_uri, redirect_uri)

    case Hexdocs.OAuth.exchange_code(code, code_verifier, opts) do
      {:ok, tokens} ->
        conn
        |> delete_session("oauth_code_verifier")
        |> delete_session("oauth_state")
        |> delete_session("oauth_return_path")
        |> store_oauth_tokens(tokens)
        |> redirect(return_path)

      {:error, {_status, %{"error_description" => description}}} ->
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: description))

      {:error, {_status, %{"error" => error}}} ->
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: error))

      {:error, reason} ->
        Logger.error("OAuth code exchange failed: #{inspect(reason)}")
        send_resp(conn, 500, Hexdocs.Templates.auth_error(reason: "Authentication failed"))
    end
  end

  defp store_oauth_tokens(conn, tokens) do
    now = NaiveDateTime.utc_now()
    expires_in = tokens["expires_in"] || 1800
    expires_at = NaiveDateTime.add(now, expires_in, :second)

    conn
    |> put_session("access_token", tokens["access_token"])
    |> put_session("refresh_token", tokens["refresh_token"])
    |> put_session("token_expires_at", expires_at)
    |> put_session("token_created_at", now)
  end

  defp try_serve_page_oauth(conn, organization, access_token) do
    expires_at = get_session(conn, "token_expires_at")
    refresh_token = get_session(conn, "refresh_token")

    cond do
      # Token needs refresh
      token_needs_refresh?(expires_at) and refresh_token ->
        case refresh_oauth_token(conn, refresh_token, organization) do
          {:ok, conn, new_access_token} ->
            serve_if_valid_oauth(conn, organization, new_access_token)

          {:error, _reason} ->
            # Refresh failed, re-authenticate
            redirect_oauth(conn, organization)
        end

      # Token expired and no refresh token
      token_expired?(expires_at) ->
        redirect_oauth(conn, organization)

      # Token is valid, serve the page
      true ->
        serve_if_valid_oauth(conn, organization, access_token)
    end
  end

  defp token_needs_refresh?(nil), do: true

  defp token_needs_refresh?(expires_at) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(expires_at, now)
    diff <= @token_refresh_buffer
  end

  defp token_expired?(nil), do: true

  defp token_expired?(expires_at) do
    NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :gt
  end

  defp refresh_oauth_token(conn, refresh_token, _organization) do
    opts = Hexdocs.OAuth.config()

    case Hexdocs.OAuth.refresh_token(refresh_token, opts) do
      {:ok, tokens} ->
        conn = store_oauth_tokens(conn, tokens)
        {:ok, conn, tokens["access_token"]}

      {:error, reason} ->
        Logger.warning("OAuth token refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp serve_if_valid_oauth(conn, organization, access_token) do
    case Hexdocs.Hexpm.verify_key(access_token, organization) do
      :ok ->
        serve_page(conn, organization)

      :refresh ->
        # Token was rejected, try to refresh or re-authenticate
        refresh_token = get_session(conn, "refresh_token")

        if refresh_token do
          case refresh_oauth_token(conn, refresh_token, organization) do
            {:ok, conn, new_access_token} ->
              # Retry verification with new token
              case Hexdocs.Hexpm.verify_key(new_access_token, organization) do
                :ok -> serve_page(conn, organization)
                _ -> redirect_oauth(conn, organization)
              end

            {:error, _} ->
              redirect_oauth(conn, organization)
          end
        else
          redirect_oauth(conn, organization)
        end

      {:error, message} ->
        send_resp(conn, 403, Hexdocs.Templates.auth_error(reason: message))
    end
  end

  defp subdomain(host) do
    app_host = Application.get_env(:hexdocs, :host)

    case String.split(host, ".", parts: 2) do
      [subdomain, ^app_host] -> subdomain
      _ -> nil
    end
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
