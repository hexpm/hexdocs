defmodule Hexdocs.QueueTest do
  use ExUnit.Case, async: true
  import Hexdocs.TestHelper
  alias Hexdocs.{HexpmMock, Store}
  alias Hexdocs.Queue.Consumer

  test "upload files", %{test: test} do
    Mox.expect(HexpmMock, :get_package, fn repo, package ->
      assert repo == "queuetest"
      assert package == "#{test}"

      %{"releases" => []}
    end)

    key = "repos/queuetest/docs/#{test}-1.0.0.tar.gz"
    tar = create_tar([{"index.html", "contents"}])
    Store.put(:repo_bucket, key, tar)

    Consumer.handle_message(put_message(key))

    files = Store.list(:docs_bucket, "queuetest/#{test}/")
    assert length(files) == 2
    assert Store.get(:docs_bucket, "queuetest/#{test}/index.html") == "contents"
    assert Store.get(:docs_bucket, "queuetest/#{test}/1.0.0/index.html") == "contents"
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
    Store.put(:docs_bucket, "queuetest/#{test}/1.0.0/index.html", "1.0.0")
    Store.put(:docs_bucket, "queuetest/#{test}/index.html", "1.0.0")

    Consumer.handle_message(put_message(key))

    files = Store.list(:docs_bucket, "queuetest/#{test}/")
    assert length(files) == 3
    assert Store.get(:docs_bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
    assert Store.get(:docs_bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
    assert Store.get(:docs_bucket, "queuetest/#{test}/index.html") == "2.0.0"
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
    Store.put(:docs_bucket, "queuetest/#{test}/2.0.0/index.html", "2.0.0")
    Store.put(:docs_bucket, "queuetest/#{test}/index.html", "2.0.0")

    Consumer.handle_message(put_message(key))

    files = Store.list(:docs_bucket, "queuetest/#{test}/")
    assert length(files) == 3
    assert Store.get(:docs_bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
    assert Store.get(:docs_bucket, "queuetest/#{test}/2.0.0/index.html") == "2.0.0"
    assert Store.get(:docs_bucket, "queuetest/#{test}/index.html") == "2.0.0"
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
    Store.put(:docs_bucket, "queuetest/#{test}/1.0.0/index.html", "garbage")
    Store.put(:docs_bucket, "queuetest/#{test}/index.html", "garbage")

    Consumer.handle_message(put_message(key))

    files = Store.list(:docs_bucket, "queuetest/#{test}/")
    assert length(files) == 2
    assert Store.get(:docs_bucket, "queuetest/#{test}/1.0.0/index.html") == "1.0.0"
    assert Store.get(:docs_bucket, "queuetest/#{test}/index.html") == "1.0.0"
  end

  test "do nothing for key that does not match", %{test: test} do
    Consumer.handle_message(put_message("queuetest/packages/#{test}"))
    assert Store.list(:docs_bucket, "queuetest/#{test}/") == []
  end

  defp put_message(key) do
    %{
      "Records" => [
        %{
          "eventName" => "ObjectCreated:Put",
          "s3" => %{"object" => %{"key" => key}}
        }
      ]
    }
  end
end
