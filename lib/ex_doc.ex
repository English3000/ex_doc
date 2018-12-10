defmodule ExDoc do
  @moduledoc false

  alias ExDoc.Config

  # Returns the ExDoc version. (Used by templates.)
  @spec version :: String.t
  def version, do: Keyword.get(Mix.Project.config, :version)

  @doc "Generates docs for the given `project`, `vsn` (version) & `options`."
  @spec generate_docs(String.t, String.t, Keyword.t) :: atom
  def generate_docs(project, version, options) when is_binary(project)
                                               and  is_binary(version)
                                               and  is_list(options)
  do
    options = normalize_options(options)
    # two side-effects
    ExDoc.Markdown.put_markdown_processor( options[:markdown_processor] )
    ExDoc.Markdown.configure_processor( options[:markdown_processor_options] )

    config =
      %Config{project:     project,
              version:     version,
              source_root: options[:source_root] || File.cwd!()} |> struct(options)

    %Config{formatter:   formatter,
            retriever:   retriever,
            source_beam: source_beam} = config

    docs = retriever.docs_from_dir(source_beam, config)
    find_formatter(formatter).run(docs, config) # below `update_output/1`
  end

  defp normalize_options(options) do
    pattern  = options[:source_url_pattern] ||
               update_url( options[:source_url], Keyword.get(options, :source_ref, ExDoc.Config.default_source_ref) )

    options_ = options
               |> Keyword.put(:source_url_pattern, pattern)
               |> update_output(options[:output])

    # Sorts `:nest_modules_by_prefix` in descending order. Helps to find longest match.
    normalized_prefixes = options_
                          |> Keyword.get(:nest_modules_by_prefix, [])
                          |> Enum.map(&inspect/1)
                          |> Enum.sort
                          |> Enum.reverse()

    Keyword.put(options_, :nest_modules_by_prefix, normalized_prefixes)
  end

  # TODO
  defp update_url(nil, _ref), do: nil
  defp update_url(url, ref),
    do: Regex.replace(~r"^https{0,1}://", url, "https://")
        |> String.trim_trailing("/")
        |> append_slug(ref)

  defp append_slug("https://github.com"    <> _ = url, ref), do: "#{url}/blob/#{ref}/%{path}#L%{line}"
  defp append_slug("https://gitlab.com"    <> _ = url, ref), do: "#{url}/blob/#{ref}/%{path}#L%{line}"
  defp append_slug("https://bitbucket.org" <> _ = url, ref), do: "#{url}/src/#{ref}/%{path}#cl-%{line}"
  defp append_slug(url, _ref),                               do: url

  defp update_output(options, output) when is_binary(output), do: Keyword.put(options, :output, String.trim_trailing(output, "/"))
  defp update_output(options, _output),                       do: options

  # Short path for programmatic interface
  defp find_formatter(module) when is_atom(module), do: module
  defp find_formatter(module_name) do
    if String.starts_with?(module_name, "ExDoc.Formatter.") do
      [module_name]
    else
      [ExDoc.Formatter, String.upcase(module_name)]
    end
    |> Module.concat()
    |> check_formatter_module(module_name)
  end

  defp check_formatter_module(module, arg), do:
    if Code.ensure_loaded?(module),
      do:   module,
      else: raise "formatter module #{inspect(arg)} not found"
end
