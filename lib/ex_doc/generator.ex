defmodule ExDoc.NodeGenerator do
  @moduledoc false

  alias ExDoc.{Config, GroupMatcher, FunctionNode, ModuleNode, TypeNode}

  def run(
    module,
    data = %{docs: {:docs_v1, anno, _, _, moduledoc, metadata, _}},
    config = %Config{
      groups_for_modules:     groups_for_modules,
      nest_modules_by_prefix: prefixes,
      source_root:            root,
      source_url_pattern:     url
    }
  ) do
    source = get_source(module, root, url)

    {title,           id}             = module_title_and_id(data)
    {nested_title,    nested_context} = nesting_info(title, prefixes)
    {function_groups, fn_docs}        = get_docs(data, source, config)

    module_group = GroupMatcher.match_module(groups_for_modules, module, id)
    docs         = fn_docs ++ get_callbacks(data, source)

    %ModuleNode{
      id:              id,
      title:           title,
      nested_title:    nested_title,
      nested_context:  nested_context,
      module:          data.name,
      group:           module_group,
      type:            data.type,
      deprecated:      metadata[:deprecated],
      function_groups: function_groups,
      docs:            Enum.sort_by(docs, &{&1.name, &1.id}),
      doc:             moduledoc,
      doc_line:        Map.get(moduledoc, "en"),
      typespecs:       get_types(data, source) |> Enum.sort_by(& &1.id),
      source_path:     source.path,
      source_url:      source_link(source, find_module_line(data) || anno_line(anno))
    }
  end

  defp get_source(module, root, url), do: %{
    url:  url,
    path: module.__info__(:compile)[:source]
          |> String.Chars.to_string
          |> Path.relative_to(root || "")
  }

  defp module_title_and_id(data = %{name: module}) do
    id = case inspect(module) do
           ":" <> inspected -> inspected
                  inspected -> inspected
         end

    if :task == Map.get(data, :type),
      do:   {task_name(module), id},
      else: Tuple.duplicate(id, 2)
  end

  defp task_name(module) do
    "Elixir.Mix.Tasks." <> name = Atom.to_string(module)

    name
    |> String.split(".")
    |> Enum.map_join(".", &Macro.underscore/1)
  end

  defp nesting_info(title, prefixes) do
    case Enum.find(prefixes, &String.starts_with?(title, &1 <> ".")) do
      nil    -> {nil, nil}
      prefix -> {String.trim_leading(title, prefix <> "."), prefix}
    end
  end

  #####################################################################

  defp get_docs(
    data = %{type: type, docs: {:docs_v1, _, _, _, _, _, fn_docs}},
    source,
    config = %Config{groups_for_functions: fn_groups}
  ) do
    groups = [{"Functions", fn _ -> true end}] ++
               Enum.map(fn_groups, fn {group, filter} ->
                 {Atom.to_string(group), filter}
               end)

    docs   = for doc <- fn_docs, include?(doc, type),
               do: get_function(doc, source, data, groups)

    {Enum.map(groups, &elem(&1, 0)), docs} # then -^ `run/3`
  end

  defp include?({{kind, _, _}, _, _, _, _}, _) when kind not in [:function, :macro],
                                                        do: false
  defp include?({{_, name, _}, _, _, :none, _}, :protocol) when name in [:impl_for, :impl_for!],
                                                        do: false
  defp include?({{_, name, _}, _, _, :none, _}, _),     do: name |> Atom.to_charlist |> hd() != ?_
  defp include?({_, _, _, :hidden, _}, _),              do: false
  defp include?(_, _),                                  do: true

  defp get_function(
    {{type, name, arity}, anno, signature, doc, metadata},
    source,
    data = %{impls: impls, specs: specs},
    groups) do
    annotations  = annotations_from_metadata(metadata)
    annotations_ =
      case {type, name, arity} do
        {:macro, _, _}      -> ["macro"  | annotations]
        {_, :__struct__, 0} -> ["struct" | annotations]
        _                   -> annotations
      end

    actual_def = actual_def(name, arity, type)

    %FunctionNode{
      id:          "#{name}/#{arity}",
      name:        name,
      arity:       arity,
      deprecated:  metadata[:deprecated],
      doc:         docstring(doc, name, arity, type, Map.fetch(impls, {name, arity})),
      doc_line:    anno_line(anno),
      defaults:    get_defaults(name, arity, metadata[:defaults] || 0)),
      signature:   Enum.join(signature, " "),
      specs:       specs |> Map.get(actual_def, []) |> get_specs(type, name),
      source_path: source.path,
      source_url:  source_link(source, find_function_line(data, actual_def) || doc_line),
      type:        type,
      group:       Enum.find_value(groups, fn {group, filter} -> filter.(metadata) && group end),
      annotations: annotations_
    } # then -^ `get_docs/3`
  end

  defp annotations_from_metadata(since: since), do: ["since #{since}" | []]
  defp annotations_from_metadata(_metadata),    do: []

  defp actual_def(name, arity, type), do:
    if type in [:macro, :macrocallback],
      do:   {String.to_atom("MACRO-" <> to_string(name)), arity + 1},
      else: {name, arity}

  defp docstring(:none, name, arity, type, {:ok, behaviour}) do
    info = "Callback implementation for `c:#{inspect(behaviour)}.#{name}/#{arity}`."

    with {:docs_v1, _, _, _, _, _, docs}     <- Code.fetch_docs(behaviour),
         key                                 =  {definition_to_callback(type), name, arity},
         {_, _, _, doc, _}                   <- List.keyfind(docs, key, 0),
         docstring when is_binary(docstring) <- Map.get(doc, "en")
    do
      "#{docstring}\n\n#{info}"
    else
      _ -> info
    end
  end
  defp docstring(doc, _, _, _, _), do: Map.get(doc, "en")

  defp anno_line(line) when is_integer(line), do: line |> abs()
  defp anno_line(line),                       do: line |> :erl_anno.line() |> abs()

  defp get_defaults(_name, _arity, 0),      do: []
  defp get_defaults(name, arity, defaults), do:
    for default <- (arity - defaults)..(arity - 1), do: "#{name}/#{default}"

  defp get_specs(defs, :macro, name) do
    Enum.map(defs, fn def ->
      Code.Typespec.spec_to_quoted(name, def) |> remove_first_macro_arg()
    end)
  end
  defp get_specs(defs, _type, name), do:
    Enum.map(defs, &Code.Typespec.spec_to_quoted(name, &1))

  defp remove_first_macro_arg({:::, info, [{name, info2, [_term_arg | rest_args]}, return]}),
    do: {:::, info, [{name, info2, rest_args}, return]}

  defp source_link(%{path: _,     url: nil}, _line), do: nil
  defp source_link(%{path: path_, url: url}, line) do
    source_url = Regex.replace(~r/%{path}/, url, path_)
    Regex.replace(~r/%{line}/, source_url, to_string(line))
  end

  defp find_function_line(%{abst_code: abst_code}, {name, arity}) do
    Enum.find_value(abst_code, fn
      {:function, anno, ^name, ^arity, _} -> anno_line(anno)
                                        _ -> nil
    end)
  end

  #####################################################################

  defp get_callbacks(%{type: :behaviour, name: name, abst_code: abst_code, docs: {:docs_v1, _, _, _, _, _, docs}}, source) do
    optional_callbacks = name.behaviour_info(:optional_callbacks)

    for {{kind, _, _}, _, _, _, _} = doc <- docs, kind in [:callback, :macrocallback],
      do: get_callback(doc, source, optional_callbacks, abst_code) # then -^ `run/3`
  end
  defp get_callbacks(_, _), do: []

  defp get_callback(callback, source, optional_callbacks, abst_code) do
    {{kind, name, arity}, anno, _, doc, metadata} = callback
    actual_def = actual_def(name, arity, kind)
    doc_line   = anno_line(anno)

    annotations  = annotations_from_metadata(metadata)
    annotations_ =
      if actual_def in optional_callbacks, do: ["optional" | annotations], else: annotations

    {:attribute, anno_, :callback, {^actual_def, specs}} =
      Enum.find(abst_code, &match?({:attribute, _, :callback, {^actual_def, _}}, &1))

    %FunctionNode{
      id:          "#{name}/#{arity}",
      name:        name,
      arity:       arity,
      deprecated:  metadata[:deprecated],
      doc:         Map.get(doc, "en"),
      doc_line:    doc_line,
      signature:   get_typespec_signature(hd(specs), arity),
      specs:       Enum.map(specs, &Code.Typespec.spec_to_quoted(name, &1)),
      source_path: source.path,
      source_url:  source_link(source, anno_line(anno_) || doc_line),
      type:        kind,
      annotations: annotations_
    }
  end

  defp definition_to_callback(:function), do: :callback
  defp definition_to_callback(:macro), do: :macrocallback

  defp get_typespec_signature({:when, _, [{:::, _, [{name, meta, args}, _]}, _]}, arity),
    do: Macro.to_string({name, meta, strip_types(args, arity)})

  defp get_typespec_signature({:::, _, [{name, meta, args}, _]}, arity),
    do: Macro.to_string({name, meta, strip_types(args, arity)})

  defp get_typespec_signature({name, meta, args}, arity),
    do: Macro.to_string({name, meta, strip_types(args, arity)})

  defp strip_types(args, arity) do
    args
    |> Enum.take(-arity)
    |> Enum.with_index()
    |> Enum.map(fn
      {{:::, _, [left, _]}, i} -> to_var(left, i)
      {{:|, _, _}, i} -> to_var({}, i)
      {left, i} -> to_var(left, i)
    end)
  end

  defp to_var({name, meta, _}, _) when is_atom(name), do: {name, meta, nil}
  defp to_var([{:->, _, _} | _], _),                  do: {:function,  [], nil}
  defp to_var({:<<>>, _, _}, _),                      do: {:binary,    [], nil}
  defp to_var({:%{}, _, _}, _),                       do: {:map,       [], nil}
  defp to_var({:{}, _, _}, _),                        do: {:tuple,     [], nil}
  defp to_var({_, _}, _),                             do: {:tuple,     [], nil}
  defp to_var(integer, _) when is_integer(integer),   do: {:integer,   [], nil}
  defp to_var(float, _) when is_integer(float),       do: {:float,     [], nil}
  defp to_var(list, _) when is_list(list),            do: {:list,      [], nil}
  defp to_var(atom, _) when is_atom(atom),            do: {:atom,      [], nil}
  defp to_var(_, i),                                  do: {:"arg#{i}", [], nil}

  defp find_module_line(%{abst_code: abst_code, name: name}) do
    Enum.find_value(abst_code, fn
      {:attribute, anno, :module, ^name} -> anno_line(anno)
      _ -> nil
    end)
  end

  #####################################################################

  defp get_types(module_data = %{docs: docs}, source) do
    {:docs_v1, _, _, _, _, _, docs} = docs

    for {{:type, _, _}, _, _, content, _} = doc <- docs, content != :hidden,
      do: get_type(doc, source, module_data.abst_code)
  end

  defp get_type(type, source, abst_code) do
    {{_, name, arity}, anno, _, doc, metadata} = type
    {:attribute, anno_, type, spec} =
      Enum.find(abst_code, fn
        {:attribute, _, type, {^name, _, args}} ->
          type in [:opaque, :type] and length(args) == arity

        _ -> false
      end)

    doc_line = anno_line(anno)

    annotations  = annotations_from_metadata(metadata)
    annotations_ = if type == :opaque, do: ["opaque" | annotations], else: annotations

    %TypeNode{
      id: "#{name}/#{arity}",
      name: name,
      arity: arity,
      type: type,
      spec: spec |> Code.Typespec.type_to_quoted() |> process_type_ast(type),
      deprecated: metadata[:deprecated],
      doc: Map.get(doc, "en"),
      doc_line: doc_line,
      signature: get_typespec_signature(spec, arity),
      source_path: source.path,
      source_url: source_link(source, anno_line(anno_) || doc_line),
      annotations: annotations_
    }
  end

  # Cut off the body of an opaque type while leaving it on a normal type.
  defp process_type_ast({:::, _, [d | _]}, :opaque), do: d
  defp process_type_ast(ast, _), do: ast
end
