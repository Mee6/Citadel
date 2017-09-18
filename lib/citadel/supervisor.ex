defmodule Citadel.Supervisor do
  use GenServer

  def worker(mod, args, name) do
    {mod, args, name}
  end

  def start_link(sup_name, workers, opts \\ []) do
    GenServer.start_link(__MODULE__, {sup_name, workers}, opts)
  end

  def init({sup_name, workers}) do
    Process.flag(:trap_exit, true)
    {:ok, {sup_name, Map.new(workers, &init_worker(sup_name, &1))}} 
  end

  defp init_worker(sup_name, {mod, args, worker_name}=spec) do
    worker_pid = lookup(sup_name, worker_name)
    do_init_worker(sup_name, spec, worker_pid)
  end

  defp do_init_worker(sup_name, spec, nil) do
    {mod, args, worker_name} = spec
    {:ok, pid} = apply(mod, :start_link, args)
    worker = %{spec: spec, pid: pid}
    register(sup_name, worker_name, pid)
    {worker_name, worker}
  end

  def handle_info({:EXIT, pid, :normal}, {sup_name, workers}) do
    workers =
      workers
      |> Enum.filter(fn {_, worker} -> pid != worker.pid end)
      |> Map.new()
    {:noreply, {sup_name, workers}}
  end

  def handle_info({:EXIT, pid, reason}, {sup_name, workers}) when reason != :normal do
    worker = Enum.find(workers, fn {worker_name, worker} ->
      pid == worker.pid
    end)

    workers =
      if worker do
        {_, worker} = worker
        {worker_name, worker} = init_worker(sup_name, worker.spec)
        Map.put(workers, worker_name, worker)
      else
        workers
      end
    {:noreply, {sup_name, workers}}
  end

  def handle_info(msg, state) do
    {:noreply, state}
  end

  def lookup(sup_name, worker_name) do
    key(sup_name, worker_name) |> Citadel.Registry.find_by_key()
  end

  def members(sup_name) do
    group(sup_name) |> Citadel.Groups.members()
  end

  def key(sup_name, worker_name), do: {:citadel_sup, sup_name, worker_name}

  def group(sup_name), do: {:citadel_sup, sup_name}

  def register(sup_name, worker_name, pid) do
    key(sup_name, worker_name) |> Citadel.Registry.register(pid)
    group(sup_name) |> Citadel.Groups.join(pid)
  end
end

