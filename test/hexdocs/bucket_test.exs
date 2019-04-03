defmodule Hexdocs.BucketTest do
  use ExUnit.Case, async: true
  alias Hexdocs.{Bucket, Store}

  @bucket :docs_private_bucket

  test "upload", %{test: test} do
    version = Version.parse!("0.0.1")
    Bucket.upload("buckettest", "#{test}", version, [], [{"index.html", "0.0.1"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.0.1/index.html") == "0.0.1"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "0.0.1"
  end

  test "overwrites main docs", %{test: test} do
    first = Version.parse!("0.0.1")
    second = Version.parse!("0.0.2")

    Bucket.upload("buckettest", "#{test}", first, [], [{"index.html", "0.0.1"}])
    Bucket.upload("buckettest", "#{test}", second, [first], [{"index.html", "0.0.2"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.0.1/index.html") == "0.0.1"
    assert Store.get(@bucket, "buckettest/#{test}/0.0.2/index.html") == "0.0.2"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "0.0.2"
  end

  test "dont overwrite main docs when uploading older versions", %{test: test} do
    first = Version.parse!("0.0.1")
    second = Version.parse!("0.0.2")

    Bucket.upload("buckettest", "#{test}", second, [], [{"index.html", "0.0.2"}])
    Bucket.upload("buckettest", "#{test}", first, [second], [{"index.html", "0.0.1"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.0.1/index.html") == "0.0.1"
    assert Store.get(@bucket, "buckettest/#{test}/0.0.2/index.html") == "0.0.2"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "0.0.2"
  end

  test "overwrite docs", %{test: test} do
    version = Version.parse!("0.0.1")

    Bucket.upload("buckettest", "#{test}", version, [], [
      {"index.html", "0.0.1"},
      {"remove.html", "remove"}
    ])

    Bucket.upload("buckettest", "#{test}", version, [], [{"index.html", "updated"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.0.1/index.html") == "updated"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "updated"
    refute Store.get(@bucket, "buckettest/#{test}/0.0.1/remove.html")
    refute Store.get(@bucket, "buckettest/#{test}/remove.html")
  end

  test "newer beta docs do not overwrite stable main docs", %{test: test} do
    first = Version.parse!("0.5.0")
    second = Version.parse!("1.0.0-beta")

    Bucket.upload("buckettest", "#{test}", first, [], [
      {"index.html", "0.5.0"},
      {"dont_remove.html", "dont remove"}
    ])

    Bucket.upload("buckettest", "#{test}", second, [first], [{"index.html", "1.0.0-beta"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.5.0/index.html") == "0.5.0"
    assert Store.get(@bucket, "buckettest/#{test}/0.5.0/dont_remove.html") == "dont remove"
    assert Store.get(@bucket, "buckettest/#{test}/1.0.0-beta/index.html") == "1.0.0-beta"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "0.5.0"
    assert Store.get(@bucket, "buckettest/#{test}/dont_remove.html") == "dont remove"
  end

  test "update main docs even with beta docs", %{test: test} do
    first = Version.parse!("0.1.0")
    second = Version.parse!("1.0.0-beta")
    third = Version.parse!("0.2.0")

    Bucket.upload("buckettest", "#{test}", first, [], [{"index.html", "0.1.0"}])
    Bucket.upload("buckettest", "#{test}", second, [first], [{"index.html", "1.0.0-beta"}])
    Bucket.upload("buckettest", "#{test}", third, [first, second], [{"index.html", "0.2.0"}])

    assert Store.get(@bucket, "buckettest/#{test}/0.1.0/index.html") == "0.1.0"
    assert Store.get(@bucket, "buckettest/#{test}/1.0.0-beta/index.html") == "1.0.0-beta"
    assert Store.get(@bucket, "buckettest/#{test}/0.2.0/index.html") == "0.2.0"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "0.2.0"
  end

  test "beta docs can overwrite beta main docs", %{test: test} do
    first = Version.parse!("1.0.0-beta")
    second = Version.parse!("2.0.0-beta")

    Bucket.upload("buckettest", "#{test}", first, [], [{"index.html", "1.0.0-beta"}])
    Bucket.upload("buckettest", "#{test}", second, [first], [{"index.html", "2.0.0-beta"}])

    assert Store.get(@bucket, "buckettest/#{test}/1.0.0-beta/index.html") == "1.0.0-beta"
    assert Store.get(@bucket, "buckettest/#{test}/2.0.0-beta/index.html") == "2.0.0-beta"
    assert Store.get(@bucket, "buckettest/#{test}/index.html") == "2.0.0-beta"
  end

  test "upload docs_config.js", %{test: test} do
    version = "1.0.0"
    all_versions = []

    Bucket.upload("buckettest", "#{test}", Version.parse!(version), all_versions, [
      {"index.html", version}
    ])

    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "1.0.0"

    version = "2.0.0"
    all_versions = [Version.parse!("1.0.0")]

    Bucket.upload("buckettest", "#{test}", Version.parse!(version), all_versions, [
      {"index.html", version}
    ])

    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "1.0.0"
    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "2.0.0"

    version = "1.1.0"
    all_versions = [Version.parse!("1.0.0"), Version.parse!("2.0.0")]

    Bucket.upload("buckettest", "#{test}", Version.parse!(version), all_versions, [
      {"index.html", version}
    ])

    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "1.0.0"
    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "1.1.0"
    assert Store.get(@bucket, "buckettest/#{test}/docs_config.js") =~ "2.0.0"
  end
end
