defmodule Hexdocs.SearchTest do
  use ExUnit.Case

  @moduletag :typesense

  setup do
    Mox.set_mox_global()

    Hexdocs.HexpmMock
    |> Mox.stub(:hexdocs_sitemap, fn -> "this is the sitemap" end)
    |> Mox.stub(:get_package, fn _repo, _package -> %{"releases" => []} end)

    orignal_search_impl = Application.get_env(:hexdocs, :search_impl)
    on_exit(fn -> Application.put_env(:hexdocs, :search_impl, orignal_search_impl) end)
    Application.put_env(:hexdocs, :search_impl, Hexdocs.Search.Typesense)

    typesense_new_collection()

    :ok
  end

  test "indexes public search_data", %{test: test} do
    search_data = """
    searchData={"items":[\
    {"type":"module","title":"Example","doc":"example text","ref":"Example.html"},\
    {"type":"function","title":"Example.test/4","doc":"does example things","ref":"Example.html#test/4"}\
    ],"content_type":"text/markdown","producer":{"name":"ex_doc","version":[48,46,51,52,46,50]}}\
    """

    key = "docs/#{test}-1.0.0.tar.gz"

    tar =
      Hexdocs.Tar.create([
        {"index.html", "contents"},
        {"dist/search_data-0F918FFD.js", search_data}
      ])

    Hexdocs.Store.put!(:repo_bucket, key, tar)
    ref = Broadway.test_message(Hexdocs.Queue, queue_put_message(key))
    assert_receive {:ack, ^ref, [_], []}

    assert [
             %{
               "document" => %{
                 "doc" => "example text",
                 "id" => "0",
                 "package" => "test indexes public search_data-1.0.0",
                 "ref" => "Example.html",
                 "title" => "Example",
                 "type" => "module"
               }
             },
             %{
               "document" => %{
                 "doc" => "does example things",
                 "id" => "1",
                 "package" => "test indexes public search_data-1.0.0",
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
                 "id" => "1",
                 "package" => "test indexes public search_data-1.0.0",
                 "ref" => "Example.html#test/4",
                 "title" => "Example.test/4",
                 "type" => "function"
               }
             }
           ] = typesense_search(%{"q" => "thing", "query_by" => "doc"})
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

  defp typesense_new_collection do
    headers = [{"x-typesense-api-key", "hexdocs"}, {"content-type", "application/json"}]

    assert {:ok, delete_status, _resp_headers, _ref} =
             :hackney.delete("http://localhost:8108/collections/hexdocs", headers)

    assert delete_status in [200, 404]

    payload = """
    {
      "name": "hexdocs",
      "token_separators": [".", "_", "-", " ", ":", "@", "/"],
      "fields": [
        {"name": "type", "type": "string", "facet": true},
        {"name": "title", "type": "string"},
        {"name": "doc", "type": "string"},
        {"name": "package", "type": "string", "facet": true}
      ]
    }
    """

    assert {:ok, 201, _resp_headers, _ref} =
             :hackney.post("http://localhost:8108/collections", headers, payload)
  end

  defp typesense_search(query) do
    url = "http://localhost:8108/collections/hexdocs/documents/search?" <> URI.encode_query(query)
    headers = [{"x-typesense-api-key", "hexdocs"}]
    assert {:ok, 200, _resp_headers, ref} = :hackney.get(url, headers)
    assert {:ok, body} = :hackney.body(ref)
    assert %{"hits" => hits} = Jason.decode!(body)
    hits
  end
end
