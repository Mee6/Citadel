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

    display_name = "#{name}"
    display_name = 
      if String.starts_with?(display_name, "Elixir.") do
        String.slice(display_name, 7..-1)
      else
        display_name
      end
    Logger.metadata(supervisor_name: display_name)

    # Building the ring
    ring =
      key
      |> Citadel.Groups.members()
      |> Enum.map(fn pid -> "#{:erlang.node(pid)}" end)
      |> HashRing.new()

    state = %{
      name:      name,
      children:  %{},
      pid_to_id: %{},
      ring:      ring
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

  def start_child(name, {id, _}=child_spec) do
    node =
      name
      |> sup_group()
      |> Citadel.Groups.members()
      |> Enum.random()
      |> GenServer.call({:which_node, id})

    GenServer.call({name, node}, {:start_child, child_spec})
  end

  def leave(name) do
    GenServer.call(name, :leave)
  end

  defp init_child(name, {id, mfa}=spec, force \\ false) do
    # Checking if a process exists with that id
    child_pid = lookup(name, id)
    if child_pid != nil and force == false do
      {:error, :already_started}
    else
      {m, f, a}  = mfa
      {:ok, pid} = apply(m, f, a)
      child      = %{spec: spec, pid: pid}
      register(name, id, pid, force)
      {id, child}
    end
  end

  def handle_call({:which_node, child_id}, _from, %{ring: ring}=state) do
    {:reply, which_node(ring, child_id), state}
  end

  def handle_call(:which_children, _from, %{children: children}=state) do
    children = Map.new(children, fn {id, %{pid: pid}} -> {id, pid} end)
    {:reply, children, state}
  end

  def handle_call({:start_child, spec}, _from, %{name: name}=state) do
    case init_child(state.name, spec) do
      {:error, e} ->
        {:reply, {:error, e}, state}
      {child_id, child} -> 
        children  = Map.put(state.children, child_id, child)
        pid_to_id = Map.put(state.pid_to_id, child.pid, child_id)

        try do
          name.after_child_start(child)
        rescue
          _e in UndefinedFunctionError -> nil
        end

        {:reply, {:ok, child.pid}, %{state | children: children, pid_to_id: pid_to_id}}
    end
  end

  def handle_call(:leave, _from, state) do
    Logger.info "Leaving cluster..."
    key = sup_group(state.name)
    Citadel.Groups.unsubsribe_groups_events(key)
    Citadel.Groups.leave(key)

    {:ok, ring} = HashRing.remove_node(state.ring, "#{node()}")
    state       = handoff_check(%{state | ring: ring})

    {:reply, :ok, state}
  end

  def handle_info({:EXIT, pid, :normal}, state) do
    child_id  = Map.get(state.pid_to_id, pid)
    children  = Map.delete(state.children, child_id)
    pid_to_id = Map.delete(state.pid_to_id, pid)
    {:noreply, %{state | children: children, pid_to_id: pid_to_id}}
  end

  def handle_info({:EXIT, pid, reason}, state) when reason != :normal do
    child_id = Map.get(state.pid_to_id, pid)
    child = Map.get(state.children, child_id)
    {children, pid_to_id} =
      if child do
        {id, child} = init_child(state.name, child.spec, true)
        {Map.put(state.children, id, child), Map.put(state.pid_to_id, pid, id)}
      else
        {state.children, state.pid_to_id}
      end
    {:noreply, %{state | children: children, pid_to_id: pid_to_id}}
  end

  def handle_info({:groups_event, :join, _key, pid}, %{ring: ring}=state) do
    remote_node = :erlang.node(pid)
    Logger.info "Adding #{remote_node} node to the ring."
    {:ok, ring} = HashRing.add_node(ring, "#{remote_node}")
    {:noreply, handoff_check(%{state | ring: ring})}
  end

  def handle_info({:groups_event, :leave, _key, pid}, %{ring: ring}=state) do
    remote_node = :erlang.node(pid)
    Logger.info "Removing #{remote_node} node from the ring."
    {:ok, ring} = HashRing.remove_node(ring, "#{remote_node}")
    {:noreply, %{state | ring: ring}}
  end

  def handle_info({:start_handoff, child_id, child}, state) do
    {id, child} = start_handoff(state.name, child_id, child)
    children    = Map.put(state.children, id, child)
    {:noreply, %{state | children: children}}
  end

  def handle_info(msg, state) do
    Logger.warn "Unhandled message #{inspect msg}"
    {:noreply, state}
  end

  defp handoff_check(state) do
    children = Enum.filter(
      state.children,
      fn {child_id, child} ->
        new_node = which_node(state.ring, child_id)
        if new_node != :erlang.node() do
          send({state.name, new_node}, {:start_handoff, child_id, child})
          false
        else
          true
        end
      end
    ) |> Map.new()

    before = Map.values(state.children) |> length()
    after_ = Map.values(children) |> length()
    Logger.info "Handed off #{before - after_} children"

    %{state | children: children}
  end

  def start_handoff(name, _child_id, child) do
    case GenServer.call(child.pid, :start_handoff) do
      :restart ->
        init_child(name, child.spec, true)
      {:handoff, handoff_state} ->
        {id, child} = init_child(name, child.spec, true)
        :ok = GenServer.call(child.pid, {:end_handoff, handoff_state})
        {id, child}
    end
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

  def register(name, child_id, pid, force \\ false) do
    key(name, child_id) |> Citadel.Registry.register(pid, force)
  end

  defp which_node(ring, child_id) do
    :"#{HashRing.find_node(ring, inspect(child_id))}"
  end
end

