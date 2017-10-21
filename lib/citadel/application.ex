defmodule Citadel.Application do
  use Application

  alias Citadel.Utils.{GroupsPartitioner, RegistryPartitioner}
  alias Citadel.{Nodes}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    :mnesia.start()

    children = [
      RegistryPartitioner.worker(),
      GroupsPartitioner.worker(),
      worker(Nodes.Supervisor, []),
      worker(Citadel.Consistency, [])
    ]
    opts = [strategy: :one_for_one, name: Citadel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
