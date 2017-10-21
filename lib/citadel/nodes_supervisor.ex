defmodule Citadel.Nodes.Supervisor do
  use Supervisor

  alias Citadel.Nodes

  def start_link do
    nodes_spec = Supervisor.child_spec(Nodes, start: {Nodes, :start_link, []})
    Supervisor.start_link([nodes_spec], strategy: :simple_one_for_one, name: __MODULE__)
  end
end

