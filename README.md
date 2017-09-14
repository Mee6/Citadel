# Citadel

A Mnesia-based distributed process registry written in Elixir.

## Installation

```elixir
def deps do
  [{:citadel, github: "mee6/citadel"}]
end
```
## Example

```elixir
>> pid = spawn(fn -> Process.sleep(10_000) end)
#PID<0.127.0>
>> Citadel.Registry.register("dumb_process", pid)
:ok
>> Citadel.Registry.find_by_key("dumb_process")
#PID<0.127.0>
```
