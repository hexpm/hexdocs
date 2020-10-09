defmodule Hexdocs.FileRewriterTest do
  use ExUnit.Case, async: true
  alias Hexdocs.FileRewriter

  test "run/1" do
    assert FileRewriter.run("index.html", "") == ""

    assert FileRewriter.run("index.html", "</head>") ==
             ~s|<script async defer data-domain="localhost" src="https://stats.localhost/js/index.js"></script></head>|

    assert FileRewriter.run(
             "index.html",
             ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
           ) ==
             ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a> for the <a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  end
end
