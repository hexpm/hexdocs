defmodule Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hook1 ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  @link_hook2 ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  @link_hooks [@link_hook1, @link_hook2]

  @analytics_hook ~s|</head>|
  @analytics_addition ~s|<script async defer data-domain="${DOMAIN}" src="https://stats.${DOMAIN}/js/index.js"></script>|

  @noindex_hook ~s|<meta name="robots" content="noindex">|

  def run(path, content) do
    content
    |> add_elixir_org_link(path)
    |> add_analytics(path)
    |> remove_noindex(path)
  end

  defp add_elixir_org_link(content, path) do
    if String.ends_with?(path, ".html") and not String.contains?(content, @link_addition) do
      String.replace(content, @link_hooks, &(&1 <> " for the " <> @link_addition))
    else
      content
    end
  end

  defp add_analytics(content, path) do
    if String.ends_with?(path, ".html") do
      String.replace(content, @analytics_hook, fn match ->
        host = Application.get_env(:hexdocs, :host)
        String.replace(@analytics_addition, "${DOMAIN}", host) <> match
      end)
    else
      content
    end
  end

  defp remove_noindex(content, path) do
    if String.ends_with?(path, ".html") do
      String.replace(content, @noindex_hook, "")
    else
      content
    end
  end
end
