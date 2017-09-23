defmodule CitadelTest do
  use ExUnit.Case
  doctest Citadel

  setup_all do
    Citadel.start()
    {:ok, %{}}
  end

  test "registry - register a pid" do
    assert :ok = Citadel.Registry.register(:foo, self())
  end

  test "registry -  find_by_key test" do
    assert :ok = Citadel.Registry.register(:foo, self())
    assert self() == Citadel.Registry.find_by_key(:foo)
  end

  test "registry - find_by_pid test" do
    assert :ok = Citadel.Registry.register(:foo, self())
    assert :ok = Citadel.Registry.register(:bar, self())
    assert :foo in Citadel.Registry.find_by_pid(self())
    assert :bar in Citadel.Registry.find_by_pid(self())
  end

  test "registry - auto remove of process in registry" do
    pid = spawn(fn -> Process.sleep(100_000) end)
    assert :ok == Citadel.Registry.register(:foo, pid)
    assert pid == Citadel.Registry.find_by_key(:foo)
    Process.exit(pid, :kill)
    Process.sleep(50)
    assert nil == Citadel.Registry.find_by_key(:foo)
  end

  test "groups - join a group" do
    assert :ok = Citadel.Groups.join(:foo, self())
  end

  test "groups - leave a group" do
    assert :ok = Citadel.Groups.join(:foo, self())
    assert :ok = Citadel.Groups.leave(:foo, self())
    assert [] = Citadel.Groups.members(:foo)
  end

  test "groups - auto leave" do
    pid = spawn(fn -> Process.sleep(100_000) end)
    assert :ok == Citadel.Groups.join(:foo, pid)
    Process.exit(pid, :kill)
    Process.sleep(50)
    assert [] == Citadel.Groups.members(:foo)
  end

  test "groups - get members" do
    assert :ok = Citadel.Groups.join(:foo, self())
    assert [self()] == Citadel.Groups.members(:foo)
  end

  test "groups - find by pid" do
    assert :ok = Citadel.Groups.join(:foo, self())
    assert [:foo] = Citadel.Groups.find_by_pid(self())
  end
end

defmodule Guilds do
  def start_link do
    children = [
      Citadel.Supervisor.worker(Guild, [0], 0),
      Citadel.Supervisor.worker(Guild, [1], 1),
      Citadel.Supervisor.worker(Guild, [2], 2),
      Citadel.Supervisor.worker(Guild, [3], 3)
    ]
    Citadel.Supervisor.start_link(Guilds, children)
  end

  def lookup(name) do
    Citadel.Supervisor.lookup(Guilds, name)
  end

  def members do
    Citadel.Supervisor.members(Guilds)
  end
end

defmodule Guild do
  use GenServer

  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    {:ok, state}
  end

  def terminate(_reason, _state), do: :ok

  def handle_info(:start, state) do
    {:noreply, state}
  end

  def handle_call(:start_handoff, from, state) do
    if rem(state, 2) == 0 do 
      msg = {:handoff, state}
      GenServer.reply(from, msg)
      {:stop, :normal, nil}
    else
      msg = :restart
      GenServer.reply(from, msg)
      {:stop, :normal, nil}
    end
  end

  def handle_call({:end_handoff, handoff_state}, _from, _state) do
    {:reply, :ok, handoff_state}
  end
end
