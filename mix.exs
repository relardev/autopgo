defmodule Autopgo.MixProject do
  use Mix.Project

  def project do
    [
      app: :autopgo,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        autopgo: [
          config_providers: [
            {Toml.Provider, [
              path: {:system, "AUTOPGO_CONFIG", ".autopgo.toml"}
            ]}
          ]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Autopgo.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16.1"},
      {:req, "~> 0.5.0"},
      {:toml, "~> 0.7"},
      {:libcluster, "~> 3.3"},
      {:swarm, "~> 3.4"},
      {:ex_unit_clustered_case, "~> 0.5", only: :test}
    ]
  end
end
