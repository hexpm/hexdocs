defmodule Hexdocs.Utils do
  @moduledoc false

  @special_package_names Map.keys(Application.compile_env!(:hexdocs, :special_packages))

  def hexdocs_url(repository, package, path) do
    "/" <> _ = path

    if repository == "hexpm" do
      host = Application.get_env(:hexdocs, :host)
      scheme = if host == "hexdocs.pm", do: "https", else: "http"
      URI.encode("#{scheme}://#{name_to_subdomain(package)}.#{host}#{path}")
    else
      host = Application.get_env(:hexdocs, :private_host)
      scheme = if host in ["hexdocs.pm", "hexorgs.pm"], do: "https", else: "http"
      URI.encode("#{scheme}://#{name_to_subdomain(repository)}.#{host}/#{package}#{path}")
    end
  end

  # Hex package and organization names allow underscores (packages
  # `^[a-z][a-z0-9_]*$`, orgs `^[a-z0-9_]+$`), but RFC 1123 hostname labels
  # and RFC 6125 wildcard SAN matching don't, and Fastly enforces strict SAN
  # matching at the HTTP edge. Map `_` -> `-` for the subdomain. For public
  # hexdocs.pm packages the Fastly Compute subdomain handler reverses the
  # mapping; for hexorgs.pm orgs `subdomain_to_name/1` reverses it here.
  def name_to_subdomain(name), do: String.replace(name, "_", "-")

  def subdomain_to_name(subdomain), do: String.replace(subdomain, "-", "_")

  def hexdocs_apex_url(path) do
    "/" <> _ = path
    host = Application.get_env(:hexdocs, :host)
    scheme = if host == "hexdocs.pm", do: "https", else: "http"
    URI.encode("#{scheme}://#{host}#{path}")
  end

  def latest_version(versions) do
    Enum.find(versions, &(&1.pre == [])) || List.first(versions)
  end

  def latest_version?(package, version, all_versions) when package in @special_package_names do
    case version do
      %Version{} ->
        latest_version?(version, all_versions)

      # main or MAJOR.MINOR
      string when is_binary(string) ->
        false
    end
  end

  def latest_version?(_package, version, all_versions) do
    latest_version?(version, all_versions)
  end

  defp latest_version?(version, all_versions) do
    pre_release? = version.pre != []
    first_release? = all_versions == []
    all_pre_releases? = Enum.all?(all_versions, &(&1.pre != []))

    cond do
      first_release? ->
        true

      all_pre_releases? ->
        latest_version = List.first(all_versions)
        Version.compare(version, latest_version) in [:eq, :gt]

      pre_release? ->
        false

      true ->
        nonpre_versions = Enum.filter(all_versions, &(&1.pre == []))
        latest_version = List.first(nonpre_versions)
        Version.compare(version, latest_version) in [:eq, :gt]
    end
  end

  def raise_async_stream_error(stream) do
    Stream.each(stream, fn
      {:ok, _} -> :ok
      {:exit, {_error, stacktrace} = reason} -> reraise(Exception.format_exit(reason), stacktrace)
    end)
  end
end
