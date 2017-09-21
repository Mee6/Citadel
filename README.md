# Citadel

Citadel is a ditribution based features lib.

## Features

- [x] Distributed process registry with groups support using Mnesia
- [x] Special supervisor with handoff support
- [x] Nodes discovery through redis
- [ ] Distributed supervisor

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

TODO

### Citadel.Nodes

If you want to enable that feature you should start your application with `CITADEL_REDIS_URL` and `CITADEL_DOMAIN` env variables. The `CITADEL_DOMAIN` is basically the name of the "cluster" you want your node to be in.

```elixir
>> Citadel.members()
[:"node1@127.0.0.1", :"node2@127.0.0.1"]
>> Citadel.join_cluster()
[true, true]
```
