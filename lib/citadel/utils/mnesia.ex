defmodule Citadel.Utils.Mnesia do
  require Logger

  def init do
    :mnesia.start()
    nodes = [node() | Node.list()]
    {:ok, _} = :mnesia.change_config(:extra_db_nodes, nodes)
  end

  def create_table(table_name, opts) do
    current_node = node()
    case :mnesia.create_table(table_name, opts) do
      {:atomic, :ok} ->
        Logger.info "#{inspect table_name} table was successfully created"
        :ok
      {:aborted, {:already_exists, table_name}} ->
        # Table already exists, trying to add copies to current node
        add_table_copy(table_name)
      other ->
        Logger.error "An error occured when creating #{inspect table_name} table. #{inspect other}"
        {:error, other}
    end
  end

  def add_table_copy(table_name) do
    current_node = node()
    # Wait for table
    :mnesia.wait_for_tables([table_name], 10_000)
    # Add copy
    case :mnesia.add_table_copy(table_name, current_node, :ram_copies) do
      {:atomic, :ok} ->
        Logger.info "Copy of #{inspect table_name} table was successfully added to current node"
        :ok
      {:aborted, {:already_exists, table_name, _node}} ->
        Logger.info "Copy of #{inspect table_name} table is already added to current node"
        :ok
      {:aborted, reason} ->
        Logger.error "An error occured while creating copy of #{inspect table_name} #{inspect reason}"
        {:error, reason}
    end
  end

  def dirty_read(table, key), do: :mnesia.dirty_read({table, key})

  def dirty_delete(table, key), do: :mnesia.dirty_delete(table, key)

  def dirty_delete_object(record), do: :mnesia.dirty_delete_object(record)

  def dirty_index_read(table, key, index), do: :mnesia.dirty_index_read(table, key, index)

  def dirty_write(tuple), do: :mnesia.dirty_write(tuple)

  def dirty_first(table), do: :mnesia.dirty_first(table)
end
