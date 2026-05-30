defmodule Odysseus.Brain.Application do
  @moduledoc """
  Brain Application — OTP Supervisor tree for all brain structures.

  Supervision strategy: one_for_one (one structure crash doesn't take down others).
  Start order matters: White Matter first, then brainstem, then cortex and subcortical.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # ─── Infrastructure (must start first) ───────────────────
      Odysseus.WhiteMatter,

      # ─── Brainstem (never-stop loop) ─────────────────────────
      Odysseus.Brainstem,

      # ─── Thalamus + Hypothalamus (routing + homeostasis) ─────
      Odysseus.Thalamus,
      Odysseus.Hypothalamus,

      # ─── Cortex (four lobes) ─────────────────────────────────
      Odysseus.FrontalLeft,
      Odysseus.FrontalRight,
      Odysseus.Parietal,
      Odysseus.Temporal,
      Odysseus.Occipital,

      # ─── Limbic system ──────────────────────────────────────
      Odysseus.Amygdala.Nif,
      Odysseus.Hippocampus.Nif,

      # ─── Basal ganglia + Cerebellum ──────────────────────────
      Odysseus.Basal.Nif,
      Odysseus.Cerebellum.Nif,

      # ─── Neuron layer (sparse associative memory) ────────────
      Odysseus.Neurons.Nif,

      # ─── Support systems ────────────────────────────────────
      Odysseus.Astrocyte,
      Odysseus.Glymphatic,

      # ─── HTTP API (TypeScript TUI connects here) ─────────────
      {Plug.Cowboy, scheme: :http, plug: Odysseus.Brain.Router, options: [port: 4001]}
    ]

    opts = [strategy: :one_for_one, name: Odysseus.Brain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
