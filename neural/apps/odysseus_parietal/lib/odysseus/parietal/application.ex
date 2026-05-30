defmodule Odysseus.Parietal.Application do
  use Application
  @impl true
  def start(_type, _args) do
    children = [Odysseus.Parietal]
    opts = [strategy: :one_for_one, name: Odysseus.Parietal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
