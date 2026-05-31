defmodule Hexdocs.FileRewriterTest do
  use ExUnit.Case, async: true
  alias Hexdocs.FileRewriter

  test "run/1" do
    assert FileRewriter.run("index.html", "") == ""

    assert FileRewriter.run("index.html", "</head>") ==
             "<script async defer src=\"https://s.localhost/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.localhost/api/event\"})</script></head>"

    assert FileRewriter.run(
             "index.html",
             ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
           ) ==
             ~s|<a rel="nofollow" href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a> for the <a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|

    assert FileRewriter.run("index.html", ~s|<meta name="robots" content="noindex">|) == ""
  end

  describe "rewrite hexdocs.pm canonical links to subdomains" do
    test "rewrites a canonical link" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link rel="canonical" href="https://hexdocs.pm/jason/Jason.html"/>|
             ) ==
               ~s|<link rel="canonical" href="https://jason.hexdocs.pm/Jason.html"/>|
    end

    test "preserves version, query and fragment in the tail" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link rel="canonical" href="https://hexdocs.pm/jason/1.4.0/Jason.html?foo=bar#decode/2"/>|
             ) ==
               ~s|<link rel="canonical" href="https://jason.hexdocs.pm/1.4.0/Jason.html?foo=bar#decode/2"/>|
    end

    test "maps underscores in the package name to hyphens" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link rel="canonical" href="https://hexdocs.pm/phoenix_html/Phoenix.HTML.html"/>|
             ) ==
               ~s|<link rel="canonical" href="https://phoenix-html.hexdocs.pm/Phoenix.HTML.html"/>|
    end

    test "rewrites the hex package" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link rel="canonical" href="https://hexdocs.pm/hex/usage.html"/>|
             ) ==
               ~s|<link rel="canonical" href="https://hex.hexdocs.pm/usage.html"/>|
    end

    test "rewrites http links to https subdomains" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link rel="canonical" href="http://hexdocs.pm/jason/Jason.html"/>|
             ) ==
               ~s|<link rel="canonical" href="https://jason.hexdocs.pm/Jason.html"/>|
    end

    test "handles href before rel in the canonical tag" do
      assert FileRewriter.run(
               "index.html",
               ~s|<link href="https://hexdocs.pm/jason/Jason.html" rel="canonical">|
             ) ==
               ~s|<link href="https://jason.hexdocs.pm/Jason.html" rel="canonical">|
    end

    test "does not rewrite body links or text" do
      for input <- [
            ~s|<a href="https://hexdocs.pm/jason/Jason.html">Jason</a>|,
            ~s|<pre><code>visit https://hexdocs.pm/jason/readme.html</code></pre>|
          ] do
        assert FileRewriter.run("index.html", input) == input
      end
    end

    test "does not rewrite other link tags" do
      input = ~s|<link rel="stylesheet" href="https://hexdocs.pm/jason/app.css">|
      assert FileRewriter.run("index.html", input) == input
    end

    test "leaves the bare apex untouched" do
      for input <- [
            ~s|<link rel="canonical" href="https://hexdocs.pm"/>|,
            ~s|<link rel="canonical" href="https://hexdocs.pm/"/>|
          ] do
        assert FileRewriter.run("index.html", input) == input
      end
    end

    test "leaves apex files untouched" do
      for input <- [
            ~s|<link rel="canonical" href="https://hexdocs.pm/sitemap.xml"/>|,
            ~s|<link rel="canonical" href="https://hexdocs.pm/foo.html"/>|
          ] do
        assert FileRewriter.run("index.html", input) == input
      end
    end

    test "does not touch canonical links that already use a subdomain" do
      for input <- [
            ~s|<link rel="canonical" href="https://jason.hexdocs.pm/Jason.html"/>|,
            ~s|<link rel="canonical" href="https://preview.hexdocs.pm/foo/Foo.html"/>|
          ] do
        assert FileRewriter.run("index.html", input) == input
      end
    end

    test "is idempotent" do
      input = ~s|<link rel="canonical" href="https://hexdocs.pm/jason/Jason.html"/>|
      once = FileRewriter.run("index.html", input)
      assert FileRewriter.run("index.html", once) == once
    end

    test "does not modify non-html files" do
      input = ~s|<link rel="canonical" href="https://hexdocs.pm/jason/Jason.html"/>|
      assert FileRewriter.run("index.js", input) == input
    end
  end

  describe "add_nofollow" do
    test "adds rel=nofollow to external links" do
      assert FileRewriter.run("index.html", ~s|<a href="https://example.com">example</a>|) ==
               ~s|<a rel="nofollow" href="https://example.com">example</a>|
    end

    test "appends nofollow to existing rel attribute" do
      assert FileRewriter.run(
               "index.html",
               ~s|<a href="https://example.com" rel="help">example</a>|
             ) ==
               ~s|<a href="https://example.com" rel="help nofollow">example</a>|
    end

    test "does not duplicate nofollow" do
      assert FileRewriter.run(
               "index.html",
               ~s|<a href="https://example.com" rel="nofollow">example</a>|
             ) ==
               ~s|<a href="https://example.com" rel="nofollow">example</a>|
    end

    test "does not add nofollow to official ecosystem links" do
      for url <- [
            "https://hex.pm/packages/foo",
            "https://hexdocs.pm",
            "https://elixir-lang.org",
            "https://www.erlang.org",
            "https://preview.hexdocs.pm/foo"
          ] do
        input = ~s|<a href="#{url}">link</a>|
        assert FileRewriter.run("index.html", input) == input
      end
    end

    test "does not add nofollow to relative links" do
      input = ~s|<a href="other.html">link</a>|
      assert FileRewriter.run("index.html", input) == input
    end

    test "does not modify non-html files" do
      input = ~s|<a href="https://example.com">example</a>|
      assert FileRewriter.run("index.js", input) == input
    end
  end
end
