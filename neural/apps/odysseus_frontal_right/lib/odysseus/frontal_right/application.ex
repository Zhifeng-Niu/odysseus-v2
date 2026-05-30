defmodule Odysseus.FrontalRight.Application do
  use Application
  @impl true
  def start(_type, _args) do
    children = [Odysseus.FrontalRight]
    opts = [strategy: :one_for_one, name: Odysseus.FrontalRight.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
