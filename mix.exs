defmodule ExDoc.Mixfile do
  use Mix.Project

  @version "0.19.1"

  def project, do: [
    app:               :ex_doc,
    version:           @version,
    description:       "ExDoc is a documentation generation tool for Elixir",
    source_url:        "https://github.com/elixir-lang/ex_doc/",
    elixir:            "~> 1.7",

    aliases:           aliases(),
    deps:              deps(),
    docs:              docs(),
    escript:           escript(),
    package:           package(),

    preferred_cli_env: [coveralls: :test],
    test_coverage:     [tool: ExCoveralls],
    xref:              [exclude: [Cmark]],
  ]

  def application, do: []

  defp aliases, do: [
    clean: [&clean_test_fixtures/1, "clean"],
    setup: ["deps.get", &setup_assets/1],
    build: [&build_assets/1, "compile --force", "docs"]
  ]

  defp clean_test_fixtures(_), do: File.rm_rf("test/tmp")
  defp setup_assets(_), do: cmd("npm", ~w(install))
  defp build_assets(_), do: cmd("npm", ~w(run build))
  defp cmd(cmd, args, opts \\ []) do
    opts = Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)
    {_, result} = System.cmd(cmd, args, opts)

    if result != 0,
      do: raise "Non-zero result (#{result}) from: #{cmd} #{Enum.map_join(args, " ", &inspect/1)}"
  end

  defp deps, do: [
    {:cmark,         "~> 0.5", only: :test},
    {:earmark,       "~> 1.2"},
    {:excoveralls,   "~> 0.3", only: :test}
    {:makeup_elixir, "~> 0.10"},
  ]

  defp docs, do: [
    main: "readme",
    extras: [
      "README.md",
      "CHANGELOG.md"
    ],
    source_ref: "v#{@version}",
    source_url: "https://github.com/elixir-lang/ex_doc",
    groups_for_modules: [
      Markdown: [
        ExDoc.Markdown,
        ExDoc.Markdown.Cmark,
        ExDoc.Markdown.Earmark
      ],
      "Formatter API": [
        ExDoc.Config,
        ExDoc.Formatter.EPUB,
        ExDoc.Formatter.HTML,
        ExDoc.Formatter.HTML.Autolink,
        ExDoc.FunctionNode,
        ExDoc.ModuleNode,
        ExDoc.TypeNode
      ]
    ]
  ]

  defp escript, do: [main_module: ExDoc.CLI]

  defp package, do: [
    licenses: ["Apache 2.0"],
    maintainers: [
      "José Valim",
      "Eksperimental",
      "Milton Mazzarri",
      "Friedel Ziegelmayer",
      "Dmitry"
    ],
    files: ["formatters", "lib", "mix.exs", "LICENSE", "CHANGELOG.md", "README.md"],
    links: %{
      "GitHub" => "https://github.com/elixir-lang/ex_doc",
      "Writing documentation" => "https://hexdocs.pm/elixir/writing-documentation.html"
    }
  ]
end
