defmodule Citadel.Backbone do
  alias Plumbus.Mnesia

  def init do
    Mnesia.init()
    nodes = [node() | Node.list()]
    Mnesia.create_table(:registry_table, [
      type: :set,
      ram_copies: nodes,
      attributes: [:key, :pid, :node],
      index: [:pid, :node],
      storage_properties: [ets: [read_concurrency: true]]
    ])
    Mnesia.create_table(:groups_table, [
      type: :bag,
      ram_copies: nodes,
      attributes: [:key, :pid, :node],
      index: [:pid, :node],
      storage_properties: [ets: [read_concurrency: true]]
    ])
  end
end
