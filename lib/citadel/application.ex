defmodule Citadel.Application do
  use Application

  alias Citadel.Utils.{GroupsPartitioner, RegistryPartitioner}
  alias Citadel.{Registry, Groups, Nodes}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    :mnesia.start()

    redis_url = Plumbus.get_env("CITADEL_REDIS_URL", "redis://localhost", :string)
    domain    = Plumbus.get_env("CITADEL_DOMAIN", nil, :string)

    children = [
      RegistryPartitioner.worker(),
      GroupsPartitioner.worker(),
      Nodes.worker(redis_url, domain),
      worker(Citadel.Consistency, [])
    ]
    opts = [strategy: :one_for_one, name: Citadel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
