for mod <- ["Registry", "Groups"] do
  defmodule :"Elixir.Citadel.Utils.#{mod}Partitioner" do
    use GenServer

    require Logger

    @max_partitions 128

    def partition_module, do: unquote(:"Elixir.Citadel.#{mod}")

    for idx <- 0..(@max_partitions-1) do
      def partition_name(unquote(idx)) do
        unquote(:"#{mod |> String.downcase()}_partition_#{idx}")
      end
    end

    def worker() do
      import Supervisor.Spec, warn: false
      worker(__MODULE__, [])
    end

    def start_link do
      GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    def init(:ok) do
      Process.flag(:trap_exit, true)

      partitions =
        for i <- 0..(System.schedulers-1) do 
          {:ok, pid} = start_partition(i)
          pid
        end
        |> List.to_tuple()

      {:ok, partitions}
    end

    def which_partition(key) do
      key
      |> :erlang.phash2(System.schedulers)
      |> partition_name()
    end

    def handle_info({:EXIT, pid, reason}, partitions) do
      Logger.warn "Citadel partition exited with reason #{inspect reason}"
      id = Enum.find_index(partitions, &(&1==pid))
      {:ok, pid} = start_partition(id)
      partitions = Tuple.insert_at(partitions, id, pid)
      {:noreply, partitions}
    end

    defp get_partition(id, partitions) do
      elem(partitions, id)
    end

    def start_partition(id) do
      :erlang.apply(partition_module(), :start_link, [[name: partition_name(id)]])
    end
  end
end
