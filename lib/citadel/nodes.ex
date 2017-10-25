defmodule Citadel.Nodes do
  use GenServer

  def start_link(redis_url, domain) do
    GenServer.start_link(__MODULE__, {redis_url, domain}, name: __MODULE__)
  end

  def worker(redis_url, domain) do
    Supervisor.Spec.worker(Citadel.Nodes, [redis_url, domain])
  end

  def init({redis_url, domain}) do
    {:ok, redis}  = Redix.start_link(redis_url)
    if domain, do: send(self(), :ping)
    {:ok, {redis, domain}}
  end

  def terminate(_reason, _state), do: :ok

  def members do
    GenServer.call(__MODULE__, :members)
  end

  def join_cluster(domain) do
    redis_url = Plumbus.get_env("CITADEL_REDIS_URL", "redis://localhost", :string)

    {:ok, _pid} = Supervisor.start_child(
      Citadel.Nodes.Supervisor,
      [redis_url, domain]
    ) 

    for node <- members() do
      true = Node.connect(node)
    end
  end

  defp prefix(domain), do: "CITADEL:#{domain}"

  defp key(domain), do: prefix(domain) <> ":nodes"

  defp key(domain, node), do: prefix(domain) <> ":node:#{node}"

  def handle_call(:members, _from, {redis, domain}) do
    nodes =
      redis
      |> Redix.command!(["SMEMBERS", key(domain)])
      |> Enum.filter_map(fn node ->
        Redix.command!(redis, ["GET", key(domain, node)]) != nil
      end, &String.to_atom/1)
    {:reply, nodes, {redis, domain}}
  end

  def handle_info(:ping, {redis, domain}) do
    node = "#{node()}"
    Redix.pipeline!(redis,[
      ["SADD", key(domain), node],
      ["SET", key(domain, node), "OK"],
      ["EXPIRE", key(domain, node), "1"]
    ])
    Process.send_after(self(), :ping, 700)
    {:noreply, {redis, domain}}
  end
end
