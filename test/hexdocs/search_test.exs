defmodule Hexdocs.SearchTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias Hexdocs.Search.Typesense

  @moduletag :typesense

  setup %{test: test} do
    Mox.set_mox_global()

    Hexdocs.HexpmMock
    |> Mox.stub(:hexdocs_sitemap, fn -> "this is the sitemap" end)
    |> Mox.stub(:get_package, fn _repo, _package -> %{"releases" => []} end)

    orignal_search_impl = Application.get_env(:hexdocs, :search_impl)
    on_exit(fn -> Application.put_env(:hexdocs, :search_impl, orignal_search_impl) end)
    Application.put_env(:hexdocs, :search_impl, Typesense)

    typesense_new_collection()

    {:ok, package: test}
  end

  defp run_upload(package, version, files) do
    tar = Hexdocs.Tar.create(files)
    key = "docs/#{package}-#{version}.tar.gz"
    Hexdocs.Store.put!(:repo_bucket, key, tar)
    ref = Broadway.test_message(Hexdocs.Queue, queue_put_message(key))
    assert_receive {:ack, ^ref, [_], []}
  end

  defp run_delete(package, version) do
    key = "docs/#{package}-#{version}.tar.gz"
    ref = Broadway.test_message(Hexdocs.Queue, queue_delete_message(key))
    assert_receive {:ack, ^ref, [_], []}
  end

  test "happy path: indexes public search_data on upload and deindexes it on delete", %{
    package: package
  } do
    version = "1.0.0"

    run_upload(package, version, [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js",
       """
       searchData={"items":[\
       {"type":"function","title":"Example.test/4","doc":"does example things","ref":"Example.html#test/4"},\
       {"type":"module","title":"Example","doc":"example text","ref":"Example.html"}\
       ],"content_type":"text/markdown","producer":{"name":"ex_doc","version":[48,46,51,52,46,50]}}\
       """}
    ])

    full_package = "#{package}-#{version}"

    assert [
             %{
               "document" => %{
                 "doc" => "example text",
                 "package" => ^full_package,
                 "proglang" => "elixir",
                 "ref" => "Example.html",
                 "title" => "Example",
                 "type" => "module"
               }
             },
             %{
               "document" => %{
                 "doc" => "does example things",
                 "package" => ^full_package,
                 "proglang" => "elixir",
                 "ref" => "Example.html#test/4",
                 "title" => "Example.test/4",
                 "type" => "function"
               }
             }
           ] = typesense_search(%{"q" => "example", "query_by" => "title"})

    assert [
             %{
               "document" => %{
                 "doc" => "does example things",
                 "proglang" => "elixir",
                 "package" => ^full_package,
                 "ref" => "Example.html#test/4",
                 "title" => "Example.test/4",
                 "type" => "function"
               }
             }
           ] = typesense_search(%{"q" => "thing", "query_by" => "doc"})

    run_delete(package, version)

    assert typesense_search(%{"q" => "example", "query_by" => "title"}) == []
  end

  test "extracts proglang from search_data if available", %{package: package} do
    run_upload(package, "1.0.0", [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js",
       """
       searchData={"items":[{"type":"module","title":"Example","doc":"example text","ref":"Example.html"}],\
       "content_type":"text/markdown","producer":{"name":"ex_doc","version":[48,46,51,52,46,50]},\
       "proglang":"erlang"}\
       """}
    ])

    assert [%{"document" => %{"title" => "Example", "proglang" => "erlang"}}] =
             typesense_search(%{
               "q" => "example",
               "query_by" => "title",
               "filter" => "proglang:erlang"
             })
  end

  test "logs an info message if search_data is not found", %{package: package} do
    original_log_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_log_level) end)

    log =
      capture_log(fn ->
        run_upload(package, "1.0.0", [{"index.html", "contents"}])
      end)

    assert log =~ "[info] Failed to find search data for #{package} 1.0.0"
  end

  test "logs an error message if search_data.js file has unexpected format", %{package: package} do
    files = [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js", "unexpected format"}
    ]

    log = capture_log(fn -> run_upload(package, "1.0.0", files) end)
    assert log =~ "[error] Unexpected search_data format for #{package} 1.0.0"
  end

  test "logs an error message if search_data.json cannot be decoded", %{package: package} do
    files = [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js", "searchData={\"items\":["}
    ]

    log = capture_log(fn -> run_upload(package, "1.0.0", files) end)

    assert log =~
             "[error] Failed to decode search data json for #{package} 1.0.0: unexpected end of input at position 10"
  end

  test "logs an error message if search_data has empty items", %{package: package} do
    files = [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js", "searchData={\"items\":[]}"}
    ]

    log = capture_log(fn -> run_upload(package, "1.0.0", files) end)

    assert log =~
             "[error] Failed to extract search items and proglang from search data for #{package} 1.0.0"
  end

  test "logs an error message if search_data has no items", %{package: package} do
    files = [
      {"index.html", "contents"},
      {"dist/search_data-0F918FFD.js", "searchData={\"not_items\":[]}"}
    ]

    log = capture_log(fn -> run_upload(package, "1.0.0", files) end)

    assert log =~
             "[error] Failed to extract search items and proglang from search data for #{package} 1.0.0"
  end

  defp queue_put_message(key) do
    Jason.encode!(%{
      "Records" => [
        %{
          "eventName" => "ObjectCreated:Put",
          "s3" => %{"object" => %{"key" => key}}
        }
      ]
    })
  end

  defp queue_delete_message(key) do
    Jason.encode!(%{
      "Records" => [
        %{
          "eventName" => "ObjectRemoved:Delete",
          "s3" => %{"object" => %{"key" => key}}
        }
      ]
    })
  end

  defp typesense_new_collection do
    collection = Typesense.collection()
    api_key = Typesense.api_key()
    headers = [{"x-typesense-api-key", api_key}, {"content-type", "application/json"}]
    payload = Jason.encode_to_iodata!(Typesense.collection_schema(collection))

    assert {:ok, 201, _resp_headers, _ref} =
             :hackney.post("http://localhost:8108/collections", headers, payload)

    on_exit(fn -> :hackney.delete("http://localhost:8108/collections/#{collection}", headers) end)
  end

  defp typesense_search(query) do
    collection = Typesense.collection()
    api_key = Typesense.api_key()

    url =
      "http://localhost:8108/collections/#{collection}/documents/search?" <>
        URI.encode_query(query)

    headers = [{"x-typesense-api-key", api_key}]
    assert {:ok, 200, _resp_headers, ref} = :hackney.get(url, headers)
    assert {:ok, body} = :hackney.body(ref)
    assert %{"hits" => hits} = Jason.decode!(body)
    hits
  end
end
