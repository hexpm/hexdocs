defmodule Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hook1 ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  @link_hook2 ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  @link_hooks [@link_hook1, @link_hook2]

  @analytics_hook ~s|</head>|
  @analytics_addition "<script async defer src=\"https://s.${DOMAIN}/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.${DOMAIN}/api/event\"})</script>"

  @noindex_hook ~s|<meta name="robots" content="noindex">|

  @official_domains ~w(hex.pm hexdocs.pm elixir-lang.org erlang.org)

  def run(path, content) do
    content
    |> add_elixir_org_link(path)
    |> add_analytics(path)
    |> remove_noindex(path)
    |> add_nofollow(path)
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

  @a_tag_re ~r/<a\s[^>]*href="https?:\/\/[^"]*"[^>]*>/
  @href_re ~r/href="(https?:\/\/[^"]*)"/

  defp add_nofollow(content, path) do
    if String.ends_with?(path, ".html") do
      Regex.replace(@a_tag_re, content, fn tag ->
        case Regex.run(@href_re, tag) do
          [_, href] ->
            if official_link?(href) do
              tag
            else
              add_rel_nofollow(tag)
            end

          _ ->
            tag
        end
      end)
    else
      content
    end
  end

  defp add_rel_nofollow(tag) do
    if tag =~ ~r/\srel="/ do
      Regex.replace(~r/\srel="([^"]*)"/, tag, fn _, existing ->
        if "nofollow" in String.split(existing) do
          ~s| rel="#{existing}"|
        else
          ~s| rel="#{existing} nofollow"|
        end
      end)
    else
      String.replace(tag, "<a ", ~s|<a rel="nofollow" |)
    end
  end

  defp official_link?(href) do
    uri = URI.parse(href)

    Enum.any?(@official_domains, fn domain ->
      uri.host == domain or (uri.host && String.ends_with?(uri.host, "." <> domain))
    end)
  end
end
