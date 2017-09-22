defmodule Citadel.Supervisor do
  use GenServer

  require Logger

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def init(name) do
    Process.flag(:trap_exit, true)

    # We join the superivsors group
    # and also subscribe to join/leave events
    key = sup_group(name)
    Citadel.Groups.join(key)
    Citadel.Groups.subsribe_groups_events(key)

    # Building the ring
    ring =
      key
      |> Citadel.Groups.members()
      |> Enum.map(fn pid -> "#{:erlang.node(pid)}" end)
      |> HashRing.new()

    state = %{
      name: name,
      children: %{},
      ring:     ring
    }

    {:ok, state}
  end

  def child_spec(mod, args, opts \\ []) do
    id       = Keyword.get(opts, :id, mod)
    function = Keyword.get(opts, :function, :start_link)
    {id, {mod, function, args}}
  end

  def start_child(name, mod, args, opts \\ []) do
    start_child(name, child_spec(mod, args, opts))
  end

  def start_child(name, child_spec) do
    node =
      name
      |> sup_group()
      |> Citadel.Groups.members()
      |> Enum.random()
      |> GenServer.call({:which_node, name})

    GenServer.call({name, node}, {:start_child, child_spec})
  end

  defp init_child(name, {id, _mfa}=spec) do
    # Checking if a process exists with that id
    child_pid = lookup(name, id)
    init_child(name, spec, child_pid)
  end

  defp init_child(name, {id, mfa}=spec, nil) do
    {m, f, a}  = mfa
    {:ok, pid} = apply(m, f, a)
    child      = %{spec: spec, pid: pid}
    register(name, id, pid)
    {id, child}
  end

  defp init_child(name, {id, mfa}=spec, pid) do
    case GenServer.call(pid, :start_handoff) do
      :restart ->
        init_child(name, spec, nil)
      {:handoff, handoff_state} ->
        {id, child} = init_child(name, spec, nil)
        :ok = GenServer.call(child.pid, {:end_handoff, handoff_state})
        {id, child}
    end
  end

  def handle_call({:which_node, child_id}, _from, %{ring: ring}=state) do
    node = :"#{HashRing.find_node(ring, child_id)}"
    {:reply, node, state}
  end

  def handle_call(:which_children, _from, %{children: children}=state) do
    children = Map.new(children, fn {id, %{pid: pid}} -> {id, pid} end)
    {:reply, children, state}
  end

  def handle_call({:start_child, spec}, _from, %{name: name, children: children}=state) do
    {child_id, child} = init_child(name, spec)
    children = Map.put(children, child_id, child)
    {:reply, {:ok, child.pid}, %{state | children: children}}
  end

  def handle_info({:EXIT, pid, :normal}, %{children: children}=state) do
    children =
      children
      |> Enum.filter(fn {_, child} -> pid != child.pid end)
      |> Map.new()
    {:noreply, %{state | children: children}}
  end

  def handle_info({:EXIT, pid, reason}, %{children: children, name: name}=state) when reason != :normal do
    res = Enum.find(children, fn {_, child} ->
      pid == child.pid
    end)

    children =
      if res do
        {_, child} = res
        {child_id, child} = init_child(name, child.spec, nil)
        Map.put(children, child_id, child)
      else
        children
      end
    {:noreply, %{state | children: children}}
  end

  def handle_info({:groups_event, :join, _key, pid}, %{ring: ring}=state) do
    remote_node = :erlang.node(pid)
    Logger.info "Adding #{remote_node} node to the ring."
    {:ok, ring} = HashRing.add_node(ring, "#{remote_node}")
    {:noreply, %{state | ring: ring}}
  end

  def handle_info({:groups_event, :leave, _key, pid}, %{ring: ring}=state) do
    remote_node = :erlang.node(pid)
    Logger.info "Removing #{remote_node} node from the ring."
    {:ok, ring} = HashRing.remove_node(ring, "#{remote_node}")
    {:noreply, %{state | ring: ring}}
  end

  def handle_info(msg, state) do
    Logger.warn "Unhandled message #{inspect msg}"
    {:noreply, state}
  end

  def lookup(name, child_id) do
    key(name, child_id) |> Citadel.Registry.find_by_key()
  end

  def which_children(pid, timeout \\ 5_000) do
    GenServer.call(pid, :which_children, timeout)
  end

  def members(name, timeout \\ 5_000) do
    sup_group(name)
    |> Citadel.Groups.members()
    |> Enum.map(&Citadel.Supervisor.which_children(&1, timeout))
    |> Enum.reduce(&Map.merge/2)
  end

  def key(name, child_id), do: {:citadel_sup_child, name, child_id}

  def sup_group(name), do: {:citadel_sup, name}

  def register(name, child_id, pid) do
    key(name, child_id) |> Citadel.Registry.register(pid)
  end
end

