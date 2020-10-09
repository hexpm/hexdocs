defmodule Hexdocs.QueueTest do
  use ExUnit.Case, async: true
  import Hexdocs.TestHelper
  alias Hexdocs.{HexpmMock, Store}

  @bucket :docs_private_bucket
  @public_bucket :docs_public_bucket

  setup do
    Mox.set_mox_global()

    Mox.expect(HexpmMock, :hexdocs_sitemap, fn ->
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
      tar = create_tar([{"index.html", "contents"}])
      Store.put(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 3
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "contents"
      assert Store.get(@bucket, "queuetest/#{test}/docs_config.js")
      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "contents"
    end

    test "upload public files", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        %{"releases" => []}
      end)

      key = "docs/#{test}-1.0.0.tar.gz"
      tar = create_tar([{"index.html", "contents"}])
      Store.put(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@public_bucket, "#{test}/")
      assert length(files) == 3
      assert Store.get(@public_bucket, "#{test}/index.html") == "contents"
      assert Store.get(@public_bucket, "#{test}/docs_config.js")
      assert Store.get(@public_bucket, "#{test}/1.0.0/index.html") == "contents"
    end

    test "overwrite main docs with newer versions", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "1.0.0", "has_docs" => true}]}
      end)

      key = "repos/queuetest/docs/#{test}-2.0.0.tar.gz"
      tar = create_tar([{"index.html", "2.0.0"}])
      Store.put(:repo_bucket, key, tar)
      Store.put(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@bucket, "queuetest/#{test}/index.html", "1.0.0")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 4
      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "2.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/docs_config.js")
    end

    test "dont overwrite main docs with older versions", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "2.0.0", "has_docs" => true}]}
      end)

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      tar = create_tar([{"index.html", "1.0.0"}])
      Store.put(:repo_bucket, key, tar)
      Store.put(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 4
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
      tar = create_tar([{"index.html", "1.0.0"}])
      Store.put(:repo_bucket, key, tar)
      Store.put(@bucket, "queuetest/#{test}/1.0.0/index.html", "garbage")
      Store.put(@bucket, "queuetest/#{test}/index.html", "garbage")

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 3
      assert Store.get(@bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/index.html") == "1.0.0"
      assert Store.get(@bucket, "queuetest/#{test}/docs_config.js")
    end

    test "do nothing for key that does not match", %{test: test} do
      ref = Broadway.test_message(Hexdocs.Queue, put_message("queuetest/packages/#{test}"))
      assert_receive {:ack, ^ref, [_], []}
      assert Store.list(@bucket, "queuetest/#{test}/") == []
    end

    test "update sitemap", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn _repo, _package ->
        %{"releases" => []}
      end)

      key = "docs/#{test}-1.0.0.tar.gz"
      tar = create_tar([{"index.html", "1.0.0"}])
      Store.put(:repo_bucket, key, tar)

      ref = Broadway.test_message(Hexdocs.Queue, put_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert Store.get(@public_bucket, "sitemap.xml") == "this is the sitemap"
    end
  end

  describe "delete object" do
    test "delete all docs when removing only version", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "queuetest"
        assert package == "#{test}"

        %{"releases" => [%{"version" => "1.0.0", "has_docs" => true}]}
      end)

      Store.put(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@bucket, "queuetest/#{test}/index.html", "1.0.0")

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert Store.list(@bucket, "queuetest/#{test}/") == []
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

      Store.put(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 2
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
      tar = create_tar([{"index.html", "1.0.0"}])
      Store.put(:repo_bucket, key, tar)

      Store.put(@bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
      Store.put(@bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@bucket, "queuetest/#{test}/index.html", "2.0.0")

      key = "repos/queuetest/docs/#{test}-2.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@bucket, "queuetest/#{test}/")
      assert length(files) == 2
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
      tar = create_tar([{"index.html", "1.0.0"}])
      Store.put(:repo_bucket, key, tar)

      Store.put(@public_bucket, "#{test}/2.0.0/index.html", "2.0.0")
      Store.put(@public_bucket, "#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@public_bucket, "#{test}/index.html", "2.0.0")

      key = "docs/#{test}-2.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      files = Store.list(@public_bucket, "#{test}/")
      assert length(files) == 2
      assert Store.get(@public_bucket, "#{test}/1.0.0/index.html") == "1.0.0"
      assert Store.get(@public_bucket, "#{test}/index.html") == "1.0.0"
    end

    test "remove both versioned and unversion when package is missing", %{test: test} do
      Mox.expect(HexpmMock, :get_package, fn repo, package ->
        assert repo == "hexpm"
        assert package == "#{test}"

        nil
      end)

      Store.put(@public_bucket, "#{test}/1.0.0/index.html", "1.0.0")
      Store.put(@public_bucket, "#{test}/index.html", "1.0.0")

      key = "docs/#{test}-1.0.0.tar.gz"
      ref = Broadway.test_message(Hexdocs.Queue, delete_message(key))
      assert_receive {:ack, ^ref, [_], []}

      assert Store.list(@public_bucket, "#{test}/") == []
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
end
