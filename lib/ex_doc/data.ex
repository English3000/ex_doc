defmodule ExDoc.ModuleData do
  @moduledoc false

  def generate_node(module, docs_chunk, config) do
    type        = get_type(module)
    module_data = %{
      name:      module,
      type:      type,
      specs:     get_specs(module),
      impls:     get_impls(module),
      abst_code: get_abstract_code(module),
      docs:      docs_chunk
    }

    case type do
      :impl -> []
      _     -> [ExDoc.NodeGenerator.run(module, module_data, config)]
    end
  end

  def get_type(module) do
    cond do
      function_exported?(module, :__struct__, 0) and
      match?(%{__exception__: true}, module.__struct__)        -> :exception

      function_exported?(module, :__protocol__, 1)             -> :protocol
      function_exported?(module, :__impl__, 1)                 -> :impl
      function_exported?(module, :behaviour_info, 1)           -> :behaviour

      match?("Elixir.Mix.Tasks." <> _, Atom.to_string(module)) -> :task
      true                                                     -> :module
    end
  end

  # Returns map :: {name, arity} => spec
  defp get_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> Map.new(specs)
      :error       -> %{}
    end
  end

  # Returns map :: {name, arity} => behaviour
  defp get_impls(module), do:
    for behaviour <- behaviours_implemented_by(module),
        callback  <- callbacks_defined_by(behaviour),
          do: {callback, behaviour}, into: %{}

  defp behaviours_implemented_by(module), do:
    for {:behaviour, list} <- module.module_info(:attributes),
        behaviour <- list,
          do: behaviour

  defp callbacks_defined_by(module) do
    case Code.Typespec.fetch_callbacks(module) do
      {:ok, callbacks} -> Keyword.keys(callbacks)
      :error           -> []
    end
  end

  defp get_abstract_code(module) do
    {^module, binary, _file} = :code.get_object_code(module)

    case :beam_lib.chunks(binary, [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {_vsn, abstract_code}}]}} -> abstract_code
      _otherwise                                            -> []
    end
  end
end
