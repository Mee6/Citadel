defmodule Citadel.Application do
  use Application

  alias Citadel.Utils.Partitioner
  alias Citadel.{Registry, Groups, Backbone}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    Backbone.init()

    children = [
      Partitioner.worker(Registry, Citadel.Registry.Partitioner),
      Partitioner.worker(Groups, Citadel.Groups.Partitioner)
    ]

    opts = [strategy: :one_for_one, name: Citadel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
