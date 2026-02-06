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

  describe "add_nofollow" do
    test "adds rel=nofollow to external links" do
      assert FileRewriter.run("index.html", ~s|<a href="https://example.com">example</a>|) ==
               ~s|<a rel="nofollow" href="https://example.com">example</a>|
    end

    test "appends nofollow to existing rel attribute" do
      assert FileRewriter.run("index.html", ~s|<a href="https://example.com" rel="help">example</a>|) ==
               ~s|<a href="https://example.com" rel="help nofollow">example</a>|
    end

    test "does not duplicate nofollow" do
      assert FileRewriter.run("index.html", ~s|<a href="https://example.com" rel="nofollow">example</a>|) ==
               ~s|<a href="https://example.com" rel="nofollow">example</a>|
    end

    test "does not add nofollow to official ecosystem links" do
      for url <- [
            "https://hex.pm/packages/foo",
            "https://hexdocs.pm/foo",
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
