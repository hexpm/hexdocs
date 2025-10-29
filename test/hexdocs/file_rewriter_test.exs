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
             ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a> for the <a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|

    assert FileRewriter.run("index.html", ~s|<meta name="robots" content="noindex">|) == ""
  end
end
