defmodule ExDoc.ModuleData do
  @moduledoc false

  def generate_node(:impl, _, _, _),             do: []
  def generate_node(type, docs, module, config), do: [%{
      name:      module,
      type:      type,
      specs:     module |> Code.Typespec.fetch_specs |> get_specs(),
      impls:     get_impls(module),
      abst_code: get_abstract_code(module),
      docs:      docs
    } |> ExDoc.NodeGenerator.run(module, config)]

  # Returns map :: {name, arity} => spec
  defp get_specs(:error),       do: %{}
  defp get_specs({:ok, specs}), do: Map.new(specs)

  # Returns map :: {name, arity} => behaviour
  defp get_impls(module), do:
    for behaviour <- module.module_info(:attributes)
                     |> Keyword.get_values(:behaviour)
                     |> List.flatten(),

        callback  <- behaviour
                     |> Code.Typespec.fetch_callbacks
                     |> callbacks_defined_by(),

          do: {callback, behaviour}, into: %{}

  defp callbacks_defined_by(:error),           do: []
  defp callbacks_defined_by({:ok, callbacks}), do: Keyword.keys(callbacks)

  defp get_abstract_code(module) do
    {^module, binary, _file} = :code.get_object_code(module)

    case :beam_lib.chunks(binary, [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {_vsn, abstract_code}}]}} -> abstract_code
                                                          _ -> []
    end
  end
end
