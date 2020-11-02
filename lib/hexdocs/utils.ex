defmodule Hexdocs.Utils do
  @moduledoc false

  def hexdocs_url(repository, path) do
    "/" <> _ = path
    host = Application.get_env(:hexdocs, :host)
    scheme = if host == "hexdocs.pm", do: "https", else: "http"
    subdomain = if repository == "hexpm", do: "", else: "#{repository}."
    "#{scheme}://#{subdomain}#{host}#{path}"
  end

  def latest_version(versions) do
    Enum.find(versions, &(&1.pre != [])) || List.first(versions)
  end

  def latest_version?(_version, []) do
    true
  end

  def latest_version?(version, all_versions) do
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
end
