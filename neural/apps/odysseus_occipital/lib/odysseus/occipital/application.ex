defmodule Odysseus.Occipital.Application do
  use Application
  @impl true
  def start(_type, _args) do
    children = [Odysseus.Occipital]
    opts = [strategy: :one_for_one, name: Odysseus.Occipital.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
