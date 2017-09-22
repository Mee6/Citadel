defmodule Citadel.Consistency do
  use GenServer

  alias Plumbus.Mnesia

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Mnesia.subscribe(:system)
    {:ok, :ok}
  end

  def terminate(_reason, _state), do: :ok

  def handle_info({:mnesia_system_event, {:mnesia_down, remote_node}}, state) do
    Logger.info "Node #{remote_node} disconnected, removing pids from registry and groups"
    remove_remote_node_registry_pids(remote_node)
    remove_remote_node_groups_pids(remote_node)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def remove_remote_node_groups_pids(remote_node) do
    for {_, key, pid, _} <- Citadel.Groups.find_by_node(remote_node) do
      Citadel.Groups.db_leave(key, pid)
    end
  end

  def remove_remote_node_registry_pids(remote_node) do
    for key <- Citadel.Registry.find_by_node(remote_node) do
      Citadel.Registry.db_unregister(key)
    end
  end
end
