defmodule Citadel.Groups do
  use GenServer

  alias Citadel.Utils.Partitioner
  alias Plumbus.Mnesia

  @table :groups_table

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_), do: {:ok, :ok}

  def join(key, pid \\ self()) do
    partition(key)
    |> GenServer.call({:join, key, pid})
  end

  def leave(key, pid \\ self()) do
    partition(key)
    |> GenServer.call({:leave, key, pid})
  end

  def members(key) do
    Mnesia.dirty_read(@table, key)
    |> Enum.map(fn {@table, _key, pid} -> pid end)
  end

  def find_by_pid(pid) do
    Mnesia.dirty_index_read(@table, pid, :pid)
    |> Enum.map(fn {@table, key, _} -> key end)
  end

  def handle_call({:join, key, pid}, _, state) do
    db_join(key, pid)
    Process.monitor(pid)
    {:reply, :ok, state}
  end

  def handle_call({:leave, key, pid}, _, state) do
    db_leave(key, pid)
    Process.demonitor(pid)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    for key <- find_by_pid(pid) do
      db_leave(key, pid)
    end
    {:noreply, state}
  end

  defp db_join(key, pid) do
    Mnesia.dirty_write({@table, key, pid})
  end

  defp db_leave(key, pid) do
    Mnesia.dirty_delete_object({@table, key, pid})
  end

  defp partition(key) do
    Partitioner.which_partition(Citadel.Groups.Partitioner, key)
  end
end
