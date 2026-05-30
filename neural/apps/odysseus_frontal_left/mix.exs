defmodule Odysseus.FrontalLeft.MixProject do
  use Mix.Project

  def project do
    [app: :odysseus_frontal_left, version: "0.1.0", build_path: "../../_build",
     config_path: "../../config/config.exs", deps_path: "../../deps",
     lockfile: "../../mix.lock", elixir: "~> 1.17",
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:odysseus_white_matter, in_umbrella: true},
      {:jason, "~> 1.4"}
    ]
  end
end
