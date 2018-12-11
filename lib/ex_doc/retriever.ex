defmodule ExDoc.Retriever do
  @moduledoc false

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  alias ExDoc.{Config, GroupMatcher, ModuleData, ModuleNode}
  alias ExDoc.Retriever.Error

  @doc "Extract modules' docs from the specified directory/-ies."
  @spec docs_from_dir(Config.t) :: [ModuleNode.t]
  def docs_from_dir(config = %Config{source_beam: dirs}) when is_list(dirs),
    do: Enum.flat_map(dirs, &docs_from_dir(%{config | source_beam: &1}))

  def docs_from_dir(config = %Config{filter_prefix: prefix,
                                     source_beam:   dir}) when is_binary(dir),
    do: if(prefix, do:   "Elixir.#{prefix}*.beam",
                   else: "*.beam")
        |> Path.expand(dir)
        |> Path.wildcard()
        |> docs_from_files(config) # Used by tests.
        
  @doc "Extract modules' docs from the specified list of files."
  @spec docs_from_files([Path.t], Config.t) :: [ModuleNode.t]
  def docs_from_files(files, config = %Config{groups_for_modules: mod_groups}),
    do: files
        |> Enum.map(fn name -> name
                               |> Path.basename(".beam")
                               |> String.to_atom() end)
        |> Enum.flat_map(& if function_exported?(&1, :__info__, 1),
                             do:   get_module(&1, config),
                             else: [])
        |> Enum.sort_by(fn %{group: group, id: id} -> {GroupMatcher.group_index(mod_groups, group), id} end)

  @doc "Get module info, then compile module."
  def get_module(module, config) do
    check_compilation(module)

    case Code.fetch_docs(module) do
      {:error, reason}                    -> raise Error, "module #{inspect(module)} " <>
                                                          "was not compiled with flag --docs: " <>
                                                          inspect(reason)
      {:docs_v1, _, _, _, :hidden, _, _}  -> []
      {:docs_v1, _, _, _, _, _, _} = docs -> ModuleData.generate_node(module, docs, config)
    end
  end

  defp check_compilation(module) do
    unless Code.ensure_loaded?(module),
      do: raise Error, "module #{inspect(module)} is not defined/available"

    unless function_exported?(Code, :fetch_docs, 1),
      do: raise Error,
            "ExDoc 0.19+ requires Elixir v1.7 and later. " <>
              "For earlier Elixir versions, make sure to depend on {:ex_doc, \"~> 0.18.0\"}"
  end
end
