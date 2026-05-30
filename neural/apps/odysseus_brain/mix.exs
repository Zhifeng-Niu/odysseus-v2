defmodule Odysseus.Brain.MixProject do
  use Mix.Project

  def project do
    [
      app: :odysseus_brain,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :cowboy, :plug],
      mod: {Odysseus.Brain.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:odysseus_white_matter, in_umbrella: true},
      {:odysseus_thalamus, in_umbrella: true},
      {:odysseus_hypothalamus, in_umbrella: true},
      {:odysseus_frontal_left, in_umbrella: true},
      {:odysseus_frontal_right, in_umbrella: true},
      {:odysseus_parietal, in_umbrella: true},
      {:odysseus_temporal, in_umbrella: true},
      {:odysseus_occipital, in_umbrella: true},
      {:odysseus_amygdala, in_umbrella: true},
      {:odysseus_hippocampus, in_umbrella: true},
      {:odysseus_basal, in_umbrella: true},
      {:odysseus_cerebellum, in_umbrella: true},
      {:odysseus_neurons, in_umbrella: true},
      {:odysseus_astrocyte, in_umbrella: true},
      {:odysseus_glymphatic, in_umbrella: true},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"}
    ]
  end
end
