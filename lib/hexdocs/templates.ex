defmodule Hexdocs.Templates do
  require EEx

  templates = Path.wildcard(Path.join(__DIR__, "templates/*"))

  Enum.each(templates, fn template ->
    name = Path.basename(template, ".html.eex") |> String.to_atom()
    EEx.function_from_file(:def, name, template, [:assigns])
  end)
end
