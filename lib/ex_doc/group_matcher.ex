defmodule ExDoc.GroupMatcher do
  @moduledoc false

  @type pattern :: Regex.t() | module() | String.t()
  @type patterns :: pattern | [pattern]
  @type group_patterns :: keyword(patterns)

  @doc "Finds the index of a given group."
  def group_index(groups, group), do: Enum.find_index(groups, fn {k, _v} -> k == group end) || -1

  @doc "Finds a matching group for the given module name or id."
  @spec match_module(group_patterns, module(), String.t()) :: atom() | nil
  def match_module(patterns, module, id) do
    match_group_patterns(patterns, fn pattern ->
      case pattern do
        %Regex{} = regex              -> Regex.match?(regex, id)
        string when is_binary(string) -> id == string
        atom                          -> atom == module
      end
    end)
  end

  @doc """
  Finds a matching group for the given extra filename
  """
  @spec match_extra(group_patterns, String.t()) :: atom() | nil
  def match_extra(group_patterns, filename) do
    match_group_patterns(group_patterns, fn pattern ->
      case pattern do
        %Regex{} = regex -> Regex.match?(regex, filename)
        string when is_binary(string) -> filename == string
      end
    end)
  end

  defp match_group_patterns(group_patterns, matcher) do
    Enum.find_value(group_patterns, fn {group, patterns} ->
      group && List.wrap(patterns) |> Enum.any?(matcher)
    end)
  end
end
