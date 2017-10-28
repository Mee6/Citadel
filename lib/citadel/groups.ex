defmodule Citadel.Groups do
  use GenServer

  alias Citadel.Utils.GroupsPartitioner, as: Partitioner
  alias Plumbus.Mnesia

  @table :groups_table

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok), do: {:ok, :ok}

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
    |> Enum.map(fn {@table, _key, pid, _node} -> pid end)
  end

  def broadcast(key, msg, excepts \\ []) do
    for pid <- members(key), not pid in excepts do
        send(pid, msg)
    end
  end

  def broadcast_local(key, msg, excepts \\ []) do
    for pid <- members(key), not pid in excepts do
      if :erlang.node(pid) == :erlang.node() do
        send(pid, msg)
      end
    end
  end

  def find_by_pid(pid) do
    Mnesia.dirty_index_read(@table, pid, :pid)
    |> Enum.map(fn {@table, key, _, _} -> key end)
  end

  def find_by_node(node) do
    Mnesia.dirty_index_read(@table, node, :node)
  end

  def subsribe_groups_events(key, pid \\ self()) do
    join({:groups_events, key}, pid)
  end

  def unsubsribe_groups_events(key, pid \\ self()) do
    join({:groups_events, key}, pid)
  end

  def handle_call({:join, key, pid}, _, state) do
    db_join(key, pid)
    Process.monitor(pid)
    {:reply, :ok, state}
  end

  def handle_call({:leave, key, pid}, _, state) do
    db_leave(key, pid)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    for key <- find_by_pid(pid) do
      db_leave(key, pid)
    end
    {:noreply, state}
  end

  def db_join(key, pid) do
    Mnesia.dirty_write({@table, key, pid, node()})
    broadcast({:groups_events, key}, {:groups_event, :join, key, pid}, [pid])
  end

  def db_leave(key, pid) do
    Mnesia.dirty_delete_object({@table, key, pid, :erlang.node(pid)})
    broadcast({:groups_events, key}, {:groups_event, :leave, key, pid}, [pid])
  end

  defp partition(key) do
    Partitioner.which_partition(key)
  end
end
