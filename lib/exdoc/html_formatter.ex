defmodule ExDoc.HTMLFormatter do
  def format_docs({name, source_path, { moduledoc, docs }}, output_path) do
    docs = generate_html_for_docs(source_path, docs)
    moduledoc = generate_html_for_moduledoc(moduledoc)
    function_docs = Enum.filter_map docs, fn(x, do: filter_by_type(x, :def)), fn(x, do: get_content(x))
    macro_docs = Enum.filter_map docs, fn(x, do: filter_by_type(x, :defmacro)), fn(x, do: get_content(x))

    bindings = [name: name, moduledoc: moduledoc, function_docs: function_docs, macro_docs: macro_docs]
    content = EEx.eval_file("#{template_path}/module_template.eex", bindings)

    Erlang.file.write_file("#{output_path}/#{name}.html", content)
  end

  def filter_by_type(function, expected) do
    { type, _ } = function
    type == expected
  end

  def get_content(function) do
    { _, content } = function
    content
  end

  defp generate_html_for_moduledoc({_, nil}) do
    nil
  end

  defp generate_html_for_moduledoc({_, false}) do
    nil
  end

  defp generate_html_for_moduledoc({_line, doc}) do
    Markdown.to_html(doc)
  end

  defp generate_html_for_docs(source_path, docs) do
    Enum.map docs, extract_docs(source_path, &1)
  end

  defp extract_docs(source_path, { { name, arity }, line, type, doc }) do
    html = if doc, do: Markdown.to_html(doc), else: ""

    function_name = "#{name}/#{arity}"
    source_link = %b{<a href="https://github.com/elixir-lang/elixir/blob/master/#{source_path}#L#{line}" target="_blank">Source</a>}
    content = %b{<div class="function"><div class="function-title" id="#{function_name}">\n<b>#{function_name}</b>\n</div>\n<div class="description">\n#{html}</div>\n#{source_link}</div>\n}
    { type, content }
  end

  defp template_path() do
    File.expand_path("../../templates", __FILE__)
  end
end
