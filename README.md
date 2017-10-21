# Citadel

Citadel is a ditribution based features lib.

## Features

- [x] Distributed process registry with groups support using Mnesia
- [x] Nodes discovery through redis
- [x] Distributed supervisor

## Installation

```elixir
def deps do
  [{:citadel, github: "mee6/citadel"}]
end
```

## Modules
### Citadel.Registry

```elixir
>> Citadel.start()
:ok
>> Citadel.Registry.register("dumb_iex_process", self())
:ok
>> Citadel.Registry.find_by_key("dumb_iex_process")
#PID<0.80.0>
>> Citadel.Groups.join("dumb_group", self())
:ok
>> Citadel.Groups.members("dumb_group")
[#PID<0.80.0>]
```

When a process dies, it'll automatically be removed from the registry and the groups it used to belong to.

### Citadel.Supervisor

This is a really simple distributed supervisor. Here's an example of how you can use it.

```elixir
defmodule Worker do
    use GenServer

    def start_link(state) do
        GenServer.start_link(__MODULE__, state)
    end

    def init(state) do
        {:ok, state}
    end
    ...
end

defmodule Worker.Supervisor do
    def start_link do
        Citadel.Supervisor.start_link(__MODULE__)
    end

    def start_worker(worker_id) do
        Citadel.Supervisor.start_child(__MODULE__, Worker, ["kek"], id: worker_id)
    end

    def worker_lookup(worker_id) do
        Citadel.Supervisor.lookup(__MODULE__, worker_id)
    end

    def members do
        Citadel.Supervisor.members(__MODULE__)
    end
end
```

We then start a node `iex --name n1@127.0.0.1 -S mix`.

```elixir
>> Citadel.start()
:ok
>> Worker.Supervisor.start_link()
{:ok, #PID<0.82.0>}
>> # Now we start a worker
nil
>> Worker.Supervisor.start_worker(0)
#PID<0.32.0>
```

Let's now connect a new node to the cluster. `iex --name n2@127.0.0.1 -S mix`.

```elixir
>> Node.connect(:"n1@127.0.0.1")
:ok
>> Citadel.start()
:ok
>> Worker.Supervisor.start_link()
{:ok, #PID<0.32.0>}
>> # Now if we start a worker it'll either be started here or on the n1 node. Depending on the hash of its id
nil
>> Worker.Supervisor.start_worker(1337)
#PID<1.43.0>
```

### Citadel.Nodes (redis backed node discovery)

If you want to enable that feature you should start your application with `CITADEL_REDIS_URL` and `CITADEL_DOMAIN` env variables. The `CITADEL_DOMAIN` is basically the name of the "cluster" you want your node to be in.

```elixir
>> Citadel.Nodes.init()
:ok
>> Citadel.members()
[:"node1@127.0.0.1", :"node2@127.0.0.1"]
>> Citadel.join_cluster()
[true, true]
```
