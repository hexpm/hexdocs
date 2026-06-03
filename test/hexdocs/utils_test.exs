defmodule Hexdocs.UtilsTest do
  use ExUnit.Case, async: true

  alias Hexdocs.Utils

  describe "hexdocs_url/3 for org repositories" do
    test "maps underscores in the org name to hyphens in the subdomain" do
      assert Utils.hexdocs_url("acme_corp", "foo", "/1.0.0") ==
               "http://acme-corp.localhost/foo/1.0.0"
    end

    test "leaves org names without underscores untouched" do
      assert Utils.hexdocs_url("acme", "foo", "/1.0.0") ==
               "http://acme.localhost/foo/1.0.0"
    end
  end

  describe "name_to_subdomain/1 and subdomain_to_name/1" do
    test "name_to_subdomain maps underscores to hyphens" do
      assert Utils.name_to_subdomain("foo_bar") == "foo-bar"
    end

    test "subdomain_to_name maps hyphens to underscores" do
      assert Utils.subdomain_to_name("foo-bar") == "foo_bar"
    end

    test "round-trips" do
      for name <- ~w(foo foo_bar a_b_c plug) do
        assert name |> Utils.name_to_subdomain() |> Utils.subdomain_to_name() == name
      end
    end
  end
end
