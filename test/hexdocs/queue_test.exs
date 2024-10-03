defmodule Hexdocs.QueueTest do
  use ExUnit.Case
  alias Hexdocs.{HexpmMock, Store}

  @bucket :docs_private_bucket
  @public_bucket :docs_public_bucket

  setup do
    Mox.set_mox_global()

    Mox.stub(HexpmMock, :hexdocs_sitemap, fn ->
      "this is the sitemap"
    end)

    :ok
  end

  describe "put object" do
    test "upload private files", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => []}
      end)

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "contents"}])
      Store.put!(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "1.0.0/index.html",
               "docs_config.js",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "contents"
      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "contents"
    end

    test "upload public files", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        %{"releases" => []}
      end)

      key = "docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "contents"}])
      Store.put!(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "#{test}/") == [
               "1.0.0/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "#{test}/index.html") == "contents"
      assert Store.get(@public_bucket, "#{test}/1.0.0/index.html") == "contents"
    end

    @tag :capture_log
    test "safe paths", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        %{"releases" => []}
      end)

      tar =
        Hexdocs.Tar.create([
          {"dir/./foo.html", ""},
          {"dir/../bar.html", ""},
          {"dir/../../baz.html", ""}
        ])

      key = "docs/#{test}-1.0.0.tar.gz"
      Store.put!(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "#{test}/1.0.0/") == [
               "bar.html",
               "dir/foo.html"
             ]
    end

    test "overwrite main docs with newer versions", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "1.0.0", "has_docs" => true}]}
      end)

      key = "repos/queuetest/docs/#{test}-2.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "2.0.0"}])
      Store.put!(:repo_bucket, key, tar)
      Store.put!(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "1.0.0")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "1.0.0/index.html",
               "2.0.0/index.html",
               "docs_config.js",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "2.0.0"
    end

    test "dont overwrite main docs with older versions", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "2.0.0", "has_docs" => true}]}
      end)

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "1.0.0"}])
      Store.put!(:repo_bucket, key, tar)
      Store.put!(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "1.0.0/index.html",
               "2.0.0/index.html",
               "docs_config.js",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/docs_config.js")
    end

    test "overwrite main docs with older versions if has_docs is false", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "2.0.0", "has_docs" => false}]}
      end)

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "1.0.0"}])
      Store.put!(:repo_bucket, key, tar)
      Store.put!(@bucket, "queuetest/#{test}/1.0.0/index.html", "garbage")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "garbage")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "1.0.0/index.html",
               "docs_config.js",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/docs_config.js")
    end

    test "do nothing for key that does not match", %{test: test} do
      ref = Broadway.test_message(Hexdocs.Queue, put_message("queuetest/packages/#{test}"))
      assert_receive {:ack, ^ref, [_], []}
      assert ls(@bucket, "queuetest/#{test}/") == []
    end

    test "update sitemap", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn _repo, _package ->
        %{"releases" => []}
      end)

      key = "docs/#{test}-1.0.0.tar.gz"

      tar =
        Hexdocs.Tar.create([
          {"index.html", "1.0.0"},
          {"logo.png", ""},
          {"Foo.html", ""}
        ])

      Store.put!(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert Store.get(@public_bucket, "sitemap.xml") == "this is the sitemap"

      sitemap = Store.get(@public_bucket, "#{test}/sitemap.xml")

      assert sitemap =~
               "<loc>http://localhost/#{URI.encode(Atom.to_string(test))}/index.html</loc>"

      assert sitemap =~ "<loc>http://localhost/#{URI.encode(Atom.to_string(test))}/Foo.html</loc>"
      refute sitemap =~ "logo.png"
    end

    test "build docs_config.js", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        %{
          "releases" => [
            %{"version" => "1.0.0", "has_docs" => true},
            %{"version" => "2.0.0", "has_docs" => false},
            %{"version" => "3.0.0", "has_docs" => true}
          ]
        }
      end)

      key = "docs/#{test}-3.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "contents"}, {"docs_config.js", "ignore"}])
      Store.put!(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "#{test}/") == [
               "3.0.0/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "#{test}/3.0.0/index.html") == "contents"
      assert Store.get(@public_bucket, "#{test}/index.html") == "contents"

      assert "var versionNodes = " <> json = Store.get(@public_bucket, "#{test}/docs_config.js")
      json = String.trim_trailing(json, ";")

      assert Jason.decode!(json) == [
               %{
                 "url" => "http://localhost/#{URI.encode(Atom.to_string(test))}/3.0.0",
                 "version" => "v3.0.0",
                 "latest" => true
               },
               %{
                 "url" => "http://localhost/#{URI.encode(Atom.to_string(test))}/1.0.0",
                 "version" => "v1.0.0",
                 "latest" => false
               }
             ]
    end

    test "special packages" do
      Mox.stub(Hexdocs.SourceRepo.Mock, :versions, fn "elixir-lang/elixir" ->
        {:ok, [Version.parse!("1.0.0")]}
      end)

      key = "docs/elixir-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "v1.0.0"}, {"docs_config.js", "use me"}])
      Store.put!(:repo_bucket, key, tar)
      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "elixir/") == [
               "1.0.0/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "elixir/1.0.0/index.html") == "v1.0.0"
      assert Store.get(@public_bucket, "elixir/docs_config.js") == "use me"
      assert Store.get(@public_bucket, "elixir/index.html") == "v1.0.0"
      assert Store.get(@public_bucket, "elixir/sitemap.xml")

      key = "docs/elixir-main.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "v2.0.0-dev"}, {"docs_config.js", "use me"}])
      Store.put!(:repo_bucket, key, tar)
      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "elixir/") == [
               "1.0.0/index.html",
               "main/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "elixir/1.0.0/index.html") == "v1.0.0"
      assert Store.get(@public_bucket, "elixir/main/index.html") == "v2.0.0-dev"
      assert Store.get(@public_bucket, "elixir/index.html") == "v1.0.0"

      Mox.stub(Hexdocs.SourceRepo.Mock, :versions, fn "elixir-lang/elixir" ->
        {:ok, [Version.parse!("1.0.0"), Version.parse!("1.1.0")]}
      end)

      key = "docs/elixir-1.1.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "v1.1.0"}, {"docs_config.js", "use me"}])
      Store.put!(:repo_bucket, key, tar)
      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "elixir/") == [
               "1.0.0/index.html",
               "1.1.0/index.html",
               "main/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "elixir/1.0.0/index.html") == "v1.0.0"
      assert Store.get(@public_bucket, "elixir/1.1.0/index.html") == "v1.1.0"
      assert Store.get(@public_bucket, "elixir/main/index.html") == "v2.0.0-dev"
      assert Store.get(@public_bucket, "elixir/index.html") == "v1.1.0"

      Mox.stub(Hexdocs.SourceRepo.Mock, :versions, fn "elixir-lang/elixir" ->
        {:ok, [Version.parse!("1.0.0"), Version.parse!("1.0.1"), Version.parse!("1.1.0")]}
      end)

      key = "docs/elixir-1.0.1.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "v1.0.1"}, {"docs_config.js", "use me"}])
      Store.put!(:repo_bucket, key, tar)
      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "elixir/") == [
               "1.0.0/index.html",
               "1.0.1/index.html",
               "1.1.0/index.html",
               "main/index.html",
               "docs_config.js",
               "index.html",
               "sitemap.xml"
             ]

      assert Store.get(@public_bucket, "elixir/1.0.0/index.html") == "v1.0.0"
      assert Store.get(@public_bucket, "elixir/1.0.1/index.html") == "v1.0.1"
      assert Store.get(@public_bucket, "elixir/1.1.0/index.html") == "v1.1.0"
      assert Store.get(@public_bucket, "elixir/main/index.html") == "v2.0.0-dev"
      assert Store.get(@public_bucket, "elixir/index.html") == "v1.1.0"
    end
  end

  describe "delete object" do
    test "delete all docs when removing only version", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "1.0.0", "has_docs" => true}]}
      end)

      Store.put!(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "1.0.0")

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == []
    end

    test "delete only version docs when removing older version", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{
          "releases" => [
            %{"version" => "1.0.0", "has_docs" => true},
            %{"version" => "2.0.0", "has_docs" => true}
          ]
        }
      end)

      Store.put!(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put!(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "2.0.0/index.html",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "2.0.0"
    end

    test "replace unversioned docs when removing version latest version", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{
          "releases" => [
            %{"version" => "1.0.0", "has_docs" => true},
            %{"version" => "2.0.0", "has_docs" => true}
          ]
        }
      end)

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "1.0.0"}])
      Store.put!(:repo_bucket, key, tar)

      Store.put!(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put!(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      key = "repos/queuetest/docs/#{test}-2.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@bucket, "queuetest/#{test}/") == [
               "1.0.0/index.html",
               "index.html"
             ]

      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "1.0.0"
    end

    test "replace public unversioned docs when removing version latest version", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        %{
          "releases" => [
            %{"version" => "1.0.0", "has_docs" => true},
            %{"version" => "2.0.0", "has_docs" => true}
          ]
        }
      end)

      key = "docs/#{test}-1.0.0.tar.gz"
      tar = Hexdocs.Tar.create([{"index.html", "1.0.0"}])
      Store.put!(:repo_bucket, key, tar)

      Store.put!(@public_bucket, "#{test}/2.0.0/index.html", "2.0.0")
      Store.put!(@public_bucket, "#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@public_bucket, "#{test}/index.html", "2.0.0")

      key = "docs/#{test}-2.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "#{test}/") == [
               "1.0.0/index.html",
               "index.html"
             ]

      assert Store.get(@public_bucket, "#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@public_bucket, "#{test}/index.html") == "1.0.0"
    end

    test "remove both versioned and unversion when package is missing", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        nil
      end)

      Store.put!(@public_bucket, "#{test}/1.0.0/index.html", "1.0.0")
      Store.put!(@public_bucket, "#{test}/index.html", "1.0.0")

      key = "docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert ls(@public_bucket, "#{test}/") == []
    end

    test "update sitemap", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn _repo, _package ->
        %{"releases" => []}
      end)

      key = "docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert Store.get(@public_bucket, "sitemap.xml") == "this is the sitemap"
    end
  end

  test "process sitemaps", %{test: test} do
    key = "docs/#{test}-1.0.0.tar.gz"
    tar = Hexdocs.Tar.create([{"index.html", "contents"}])
    Store.put!(:repo_bucket, key, tar)

    refute Store.get(@public_bucket, "#{test}/sitemap.xml")

    ref = Broadway.test_message(Hexdocs.Queue, Jason.encode!(%{"hexdocs:sitemap" => key}))
    assert_receive {:ack, ^ref, [_], []}

    assert Store.get(@public_bucket, "#{test}/sitemap.xml")
  end

  test "paths_for_sitemaps/0" do
    Store.Local.delete(:repo_bucket, "docs")
    Store.put!(:repo_bucket, "docs/foo-1.0.0.tar.gz", "")
    Store.put!(:repo_bucket, "docs/bar-1.0.0.tar.gz", "")
    Store.put!(:repo_bucket, "docs/bar-1.1.0.tar.gz", "")
    Store.put!(:repo_bucket, "docs/baz-1.0.0.tar.gz", "")
    Store.put!(:repo_bucket, "docs/baz-2.0.0-rc.1.tar.gz", "")
    Store.put!(:repo_bucket, "docs/qux-1.0.0-rc.1.tar.gz", "")
    Store.put!(:repo_bucket, "docs/qux-1.0.0-rc.2.tar.gz", "")
    Store.put!(:repo_bucket, "docs/elixir-1.0.0.tar.gz", "")
    Store.put!(:repo_bucket, "docs/elixir-2.0.0.tar.gz", "")

    assert Enum.to_list(Hexdocs.Queue.paths_for_sitemaps()) ==
             [
               "docs/bar-1.1.0.tar.gz",
               "docs/baz-1.0.0.tar.gz",
               "docs/elixir-2.0.0.tar.gz",
               "docs/foo-1.0.0.tar.gz",
               "docs/qux-1.0.0-rc.2.tar.gz"
             ]
  end

  defp put_message(key) do
    Jason.encode!(%{
      "Records" => [
        %{
          "eventName" => "ObjectCreated:Put",
          "s3" => %{"object" => %{"key" => key}}
        }
      ]
    })
  end

  defp delete_message(key) do
    Jason.encode!(%{
      "Records" => [
        %{
          "eventName" => "ObjectRemoved:Delete",
          "s3" => %{"object" => %{"key" => key}}
        }
      ]
    })
  end

  defp ls(bucket, prefix) do
    Store.list(bucket, prefix)
    |> Enum.map(&String.trim_leading(&1, prefix))
    |> Enum.sort_by(fn path ->
      version = path |> String.split("/") |> hd()

      versioned? =
        version == "main" or
          match?({:ok, _}, Version.parse(version)) or
          match?({:ok, _}, Version.parse(version <> ".0"))

      {not versioned?, path}
    end)
  end
end
