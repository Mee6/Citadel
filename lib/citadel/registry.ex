defmodule Citadel.Registry do
  alias Citadel.Utils.RegistryPartitioner, as: Partitioner
  alias Plumbus.Mnesia

  require Logger

  @table :registry_table

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok), do: {:ok, :ok}

  def terminate(_reason, _state), do: :ok

  def register(key, pid \\ self()) do
    partition(key)
    |> GenServer.call({:register, key, pid})
  end

  def unregister(key) do
    partition(key)
    |> GenServer.call({:unregister, key})
  end

  def find_by_key(key) do
    case Mnesia.dirty_read(@table, key) do
      [{_, ^key, pid, _node}] -> pid
      _ -> nil
    end
  end

  def find_by_pid(pid) do
    Mnesia.dirty_index_read(@table, pid, :pid)
    |> Enum.map(fn {@table, key, ^pid, _node} -> key end)
  end

  def find_by_node(node) do
    Mnesia.dirty_index_read(@table, node, :node)
    |> Enum.map(fn {@table, key, _pid, ^node} -> key end)
  end

  def handle_call({:register, key, pid}, _, state) do
    case find_by_key(key) do
      nil ->
        db_register(key, pid)
        Process.monitor(pid)
        {:reply, :ok, state}
      _pid ->
        {:reply, {:error, :already_exists}, state}
    end
  end

  def handle_call({:unregister, key}, _, state) do
    case find_by_key(key) do
      nil -> {:reply, :ok, state}
      _pid ->
        db_unregister(key)
        {:reply, :ok, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    for key <- find_by_pid(pid) do
      db_unregister(key)
    end
    {:noreply, state}
  end

  def db_register(key, pid) do
    Mnesia.dirty_write({@table, key, pid, node()})
  end

  def db_unregister(key) do
    Mnesia.dirty_delete(@table, key)
  end

  defp partition(key) do
    Partitioner.which_partition(key)
  end
end
