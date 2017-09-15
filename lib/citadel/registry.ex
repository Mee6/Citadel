defmodule Citadel.Registry do
  alias Citadel.Utils.Partitioner
  alias Plumbus.Mnesia

  @table :registry_table

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_), do: {:ok, :ok}

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
      [{_, ^key, pid}] -> pid
      _ -> nil
    end
  end

  def find_by_pid(pid) do
    Mnesia.dirty_index_read(@table, pid, :pid)
    |> Enum.map(fn {@table, key, ^pid} -> key end)
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
      pid ->
        db_unregister(key)
        Process.demonitor(pid)
        {:reply, :ok, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    for key <- find_by_pid(pid) do
      db_unregister(key)
    end
    {:noreply, state}
  end

  defp db_register(key, pid) do
    Mnesia.dirty_write({@table, key, pid})
  end

  defp db_unregister(key) do
    Mnesia.dirty_delete(@table, key)
  end

  defp partition(key) do
    Partitioner.which_partition(Citadel.Registry.Partitioner, key)
  end
end
