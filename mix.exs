defmodule Chat.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [
        Phoenix.CodeReloader
      ]
    ]
    |> more_project()
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Chat.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
    |> more_application()
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "1.0.17"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto, "~> 3.7"},
      {:ecto_sql, "~> 3.7"},
      {:postgrex, "~> 0.16"},
      {:plug_cowboy, "~> 2.5"},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:jason, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
    |> more_deps()
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
    |> more_aliases()
  end

  ################################
  defp more_project(project) do
    Keyword.merge(project,
      consolidate_protocols: Mix.env() != :dev,
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:ex_unit]],
      releases: [
        chat: [
          version: build_version(),
          applications: [chat: :permanent]
        ]
      ]
    )
  end

  defp more_application(app) do
    update_in(app, [:extra_applications], &(&1 ++ [:curvy, :os_mon]))
  end

  defp more_deps(deps) do
    deps ++
      [
        {:logger_backends, "~> 1.0"},
        {:tidewave, "~> 0.1", only: [:dev]},
        {:igniter, "~> 0.5", only: [:dev, :test]},
        # Chat deps
        {:qr_code, "~> 2.2.1"},
        # electric_cubdb instead of cubdb to avoid conflicts with Electric
        {:electric_cubdb, "~> 2.0", override: true},
        {:curvy, "~> 0.3.1"},
        {:struct_access, "~> 1.1"},
        {:uuid, "~> 1.1"},
        {:uuidv7, "~> 0.2"},
        {:ip, "~> 2.0"},
        {:slipstream, "~> 1.1"},
        {:onvif, github: "sergey-lukianov/onvif"},
        {:keyx, "~> 0.4.1"},
        {:combinatorics, "~> 0.1.0"},
        {:timex, "~> 3.7"},
        {:tzdata, "~> 1.1"},

        # Phoenix extras
        {:phoenix_html_helpers, "~> 1.0"},
        {:phoenix_view, "~> 2.0"},
        {:cors_plug, "~> 3.0"},

        # Build tooling
        {:live_vue, "~> 0.5"},
        {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
        {:sobelow, "~> 0.8", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.14", only: [:test]},
        {:rewire, "~> 0.9", only: [:dev, :test]},
        {:live_isolated_component,
         github: "sergey-lukianov/live_isolated_component", only: [:dev, :test]},
        {:lazy_html, ">= 0.1.0", only: :test},

        # other
        {:absinthe, "~> 1.7"},
        {:absinthe_plug, "~> 1.5"},
        {:neuron, "~> 5.1"},
        {:temp, "~> 0.4.7"},
        {:floki, ">= 0.30.0", only: :test},
        {:mock, "~> 0.3.0", only: :test},
        {:zstream, "~> 0.6"},
        {:ua_parser, github: "beam-community/ua_parser"},
        {:httpoison, "~> 2.0"},
        {:req, "~> 0.5"},
        {:tesla, "~> 1.7"},

        # ElectricSQL / Phoenix.Sync
        {:electric, "~> 1.1"},
        {:phoenix_sync, "~> 0.6.1"},
        {:electric_client,
         github: "salseeg/electric",
         sparse: "packages/elixir-client",
         branch: "buckitup-patches",
         override: true},

        # Internal
        {:toolbox, github: "Buckitup-chat/toolbox"}
      ]
  end

  defp more_aliases(aliases) do
    Keyword.merge(aliases,
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["cmd --cd assets npm install"],
      "assets.build": [
        "cmd --cd assets npm run build"
      ],
      "assets.deploy": [
        "cmd --cd assets npm run build",
        "phx.digest"
      ]
    )
  end

  defp build_version do
    case System.cmd("git", ~w|log -1 --date=format:%Y-%m-%d --format=%cd_%h|) do
      {hash, 0} -> String.trim(hash)
      _ -> "gigalixir"
    end
  end
end
