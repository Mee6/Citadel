defmodule Citadel.Supervisor do
  use GenServer

  require Logger

  def worker(mod, args, name) do
    {mod, args, name}
  end

  def start_link(sup_name, workers) do
    GenServer.start_link(__MODULE__, {sup_name, workers}, name: sup_name)
  end

  def init({sup_name, workers}) do
    Process.flag(:trap_exit, true)

    key = sup_group(sup_name)
    Citadel.Groups.join(key)
    Citadel.Groups.subsribe_groups_events(key)

    ring =
      key
      |> Citadel.Groups.members()
      |> Enum.map(fn pid -> "#{:erlang.node(pid)}" end)
      |> HashRing.new()

    {:ok, {sup_name, Map.new(workers, &init_worker(sup_name, &1)), ring}} 
  end

  def start_child(sup_name, mod, args, name) do
    node = GenServer.call(sup_name, {:which_node, name})
    GenServer.call({sup_name, node}, {:start_child, worker(mod, args, name)})
  end

  defp init_worker(sup_name, {_, _, worker_name}=spec) do
    worker_pid = lookup(sup_name, worker_name)
    init_worker(sup_name, spec, worker_pid)
  end

  defp init_worker(sup_name, spec, nil) do
    {mod, args, worker_name} = spec
    {:ok, pid} = apply(mod, :start_link, args)
    worker = %{spec: spec, pid: pid}
    register(sup_name, worker_name, pid)
    send(pid, :start)
    Logger.info "[#{sup_name} supervisor] Started worker #{inspect worker_name} (fresh start)"
    {worker_name, worker}
  end

  defp init_worker(sup_name, spec, pid) do
    case GenServer.call(pid, :start_handoff) do
      :restart ->
        init_worker(sup_name, spec, nil)
      {:handoff, handoff_state} ->
        {mod, args, worker_name} = spec
        {:ok, pid} = apply(mod, :start_link, args)
        worker = %{spec: spec, pid: pid}
        register(sup_name, worker_name, pid)
        :ok = GenServer.call(pid, {:end_handoff, handoff_state})
        Logger.info "[#{sup_name} supervisor] Started #{inspect worker_name} (handoff)"
        {worker_name, worker}
    end
  end

  def handle_call({:which_node, name}, _from, {sup_name, workers, ring}) do
    {:reply, :"#{HashRing.find_node(ring, name)}", {sup_name, workers, ring}}
  end

  def handle_call({:start_child, spec}, _from, {sup_name, workers, ring}) do
    {worker_name, worker} = init_worker(sup_name, spec)
    workers = Map.put(workers, worker_name, worker)
    {:reply, {:ok, worker.pid}, {sup_name, workers, ring}}
  end

  def handle_info({:EXIT, pid, :normal}, {sup_name, workers, ring}) do
    workers =
      workers
      |> Enum.filter(fn {_, worker} -> pid != worker.pid end)
      |> Map.new()
    {:noreply, {sup_name, workers, ring}}
  end

  def handle_info({:EXIT, pid, reason}, {sup_name, workers, ring}) when reason != :normal do
    worker = Enum.find(workers, fn {_, worker} ->
      pid == worker.pid
    end)

    workers =
      if worker do
        {_, worker} = worker
        {worker_name, worker} = init_worker(sup_name, worker.spec, nil)
        Map.put(workers, worker_name, worker)
      else
        workers
      end
    {:noreply, {sup_name, workers, ring}}
  end

  def handle_info({:groups_event, :join, _key, pid}, {sup_name, workers, ring}) do
    remote_node = :erlang.node(pid)
    Logger.info "Adding #{remote_node} node to the ring."
    {:ok, ring} = HashRing.add_node(ring, "#{remote_node}")
    {:noreply, {sup_name, workers, ring}}
  end

  def handle_info({:groups_event, :leave, _key, pid}, {sup_name, workers, ring}) do
    remote_node = :erlang.node(pid)
    Logger.info "Removing #{remote_node} node to the ring."
    {:ok, ring} = HashRing.remove_node(ring, "#{remote_node}")
    {:noreply, {sup_name, workers, ring}}
  end

  def handle_info(msg, state) do
    Logger.warn "Unhandled message #{inspect msg}"
    {:noreply, state}
  end

  def lookup(sup_name, worker_name) do
    key(sup_name, worker_name) |> Citadel.Registry.find_by_key()
  end

  def members(sup_name) do
    group(sup_name) |> Citadel.Groups.members()
  end

  def key(sup_name, worker_name), do: {:citadel_sup_worker, sup_name, worker_name}

  def group(sup_name), do: {:citadel_sup_workers, sup_name}

  def sup_group(sup_name), do: {:citadel_sup, sup_name}

  def register(sup_name, worker_name, pid) do
    key(sup_name, worker_name) |> Citadel.Registry.register(pid)
    group(sup_name) |> Citadel.Groups.join(pid)
  end
end

