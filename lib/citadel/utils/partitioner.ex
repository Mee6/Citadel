defmodule Citadel.Utils.Partitioner do
  use GenServer

  require Logger

  def worker(module, name) do
    import Supervisor.Spec, warn: false
    worker(__MODULE__,
           [module, [name: name]],
           id: name)
  end

  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, module, opts)
  end

  def init(module) do
    Process.flag(:trap_exit, true)
    {:ok, {module, Tuple.duplicate(nil, System.schedulers)}}
  end

  def which_partition(partitioner, key, timeout \\ 5_000) do
    GenServer.call(partitioner, {:which_partition, key}, timeout)
  end

  def handle_call({:which_partition, key}, _from, {module, partitions}=state) do
    {partition_pid, partitions} = 
      key
      |> :erlang.phash2(tuple_size(partitions))
      |> get_partition(state)

    {:reply, partition_pid, {module, partitions}}
  end

  def handle_info({:EXIT, pid, reason}, {module, partitions}=state) do
    Logger.warn "Citadel partition exited with reason #{inspect reason}"
    id = Enum.find_index(partitions, &(&1==pid))
    {:ok, pid} = start_partition(state)
    partitions = Tuple.insert_at(partitions, id, pid)
    {:noreply, {module, partitions}}
  end

  defp get_partition(id, {_, partitions}=state) do
    case elem(partitions, id) do
      nil ->
        {:ok, pid} = start_partition(state)
        {pid, Tuple.insert_at(partitions, id, pid)}
      pid ->
        {pid, partitions}
    end
  end

  defp start_partition({module, _}=_state) do
    :erlang.apply(module, :start_link, [])
  end
end
