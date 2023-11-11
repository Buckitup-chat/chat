defmodule Chat.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      # compilers: [] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:ex_unit]],
      releases: [
        chat: [
          version: build_version(),
          applications: [chat: :permanent]
        ]
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Chat.Application, []},
      extra_applications: [:logger, :runtime_tools, :curvy, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:neuron, "~> 5.1"},
      {:poison, "~> 5.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto, "~> 3.7"},
      {:temp, "~> 0.4.7"},
      {:tzdata, "~> 1.1"},
      {:qr_code, "~> 2.2.1"},
      {:cubdb, "~> 2.0"},
      {:curvy, "~> 0.3.1"},
      {:struct_access, "~> 1.1"},
      {:uuid, "~> 1.1"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.18"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:esbuild, "~> 0.3", runtime: Mix.env() == :dev && Mix.target() == :host},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.8", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:timex, "~> 3.7"},
      {:zstream, "~> 0.6"},
      {:ua_parser, github: "beam-community/ua_parser"},
      {:excoveralls, "~> 0.14", only: [:test]},
      {:rewire, "~> 0.9.0", only: [:test]},
      {:keyx, "~> 0.4.1"},
      {:combinatorics, "~> 0.1.0"},
      {:httpoison, "~> 2.0"},
      {:onvif, github: "sergey-lukianov/onvif"},
      {:tesla, "~> 1.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      "assets.deploy": ["esbuild default --minify", "tailwind default --minify", "phx.digest"]
    ]
  end

  defp build_version do
    case System.cmd("git", ~w|log -1 --date=format:%Y-%m-%d --format=%cd_%h|) do
      {hash, 0} -> String.trim(hash)
      _ -> "gigalixir"
    end
  end
end
