defmodule SEC_Node do
  use GenServer
  require Logger
  alias NodeTable
  alias UUID

  alias TcpConnection
  # Public
  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: {:via, Registry, {Registry.SEC_Node, {opts[:host], opts[:port]}}}
    )
  end

  def describe(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, :describe)
  end

  def activate(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, :activate)
  end

  def deactivate(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, :deactivate)
  end

  def change(node_id, module, parameter, value) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, {:change, module, parameter, value})
  end

  def execute_command(node_id, module, command, value) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, {:do, module, command, value})
  end

  def execute_command(node_id, module, command) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node, node_id)
    GenServer.call(sec_node_pid, {:do, module, command, "null"})
  end

  # callbacks
  @impl true
  def init(opts) do
    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host], opts[:port]},
      equipment_id: nil,
      reconnect_backoff: opts[:reconnect_backoff] || 5000,
      description: nil,
      active: false,
      uuid: UUID.uuid1()
    }

    TcpConnection.connect_supervised(opts)
    NodeTable.start(state.node_id)

    {:ok, state}
  end

  @impl true
  def handle_call(:describe, _from, %{node_id: node_id} = state) do
    Logger.info("Describe Message sent")
    TcpConnection.send_message(node_id, ~c"describe .\n")

    receive do
      {:describe, specifier, structure_report} ->
        Logger.info("Description received")
        equipment_id = Map.get(structure_report, "equipment_id")
        updated_state = %{state | description: structure_report, equipment_id: equipment_id}
        {:reply, {:description, specifier, structure_report}, updated_state}
    after
      5000 -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:activate, _from, %{node_id: node_id} = state) do
    Logger.info("Activate Message sent")
    TcpConnection.send_message(node_id, ~c"activate\n")

    receive do
      {:active} ->
        Logger.info("Node Active")
        updated_state = %{state | active: true}
        {:reply, :active, updated_state}
    after
      5000 -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:deactivate, _from, %{node_id: node_id} = state) do
    Logger.info("Deactivate Message sent")
    TcpConnection.send_message(node_id, ~c"deactivate\n")

    receive do
      {:inactive} ->
        Logger.info("Node Inactive")
        updated_state = %{state | active: false}
        {:reply, :active, updated_state}
    after
      5000 -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:change, module, parameter, value}, _from, %{node_id: node_id} = state) do
    message = "change #{module}:#{parameter} #{value}\n"

    Logger.info("Change Message '#{String.trim_trailing(message)}' sent")

    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:changed, r_module, r_parameter, data_report} ->
        Logger.info("Value of #{module}:#{parameter} changed to #{Jason.encode!(data_report)}")
        {:reply, {:changed, r_module, r_parameter, data_report}, state}
    after
      5000 -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:do, module, command, value}, _from, %{node_id: node_id} = state) do
    message = "do #{module}:#{command} #{value}\n"

    Logger.info("Do Message '#{String.trim_trailing(message)}' sent")
    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:done, r_module, r_command, data_report} ->
        Logger.info(
          "Command #{module}:#{command} executed and returned: #{Jason.encode!(data_report)}"
        )

        {:reply, {:done, r_module, r_command, data_report}, state}
    after
      5000 -> {:reply, :error, state}
    end
  end

  ### TODO handle non sync messages gracefully (ie if they arrive after timeout)
  @impl true
  def handle_info({:active}, state) do
    Logger.warning("received async ACTIVE message")
    updated_state = %{state | active: true}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:inactive}, state) do
    Logger.warning("received async INACTIVE message")
    updated_state = %{state | active: false}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:pong, id, data}, state) do
    Logger.warning("received async PONG message id:#{id}, data:#{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:describe, _specifier, structure_report}, state) do
    equipment_id = Map.get(structure_report, "equipment_id")
    updated_state = %{state | description: structure_report, equipment_id: equipment_id}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:done, module, command, data_report}, state) do
    Logger.warning("received async DONE message #{module}:#{command} data: #{data_report}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:reply, module, parameter, data_report}, state) do
    Logger.warning("received async REPLY message #{module}:#{parameter} data: #{data_report}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:changed, module, parameter, data_report}, state) do
    Logger.warning("received async CHANGED message #{module}:#{parameter} data: #{data_report}")
    {:noreply, state}
  end
end

defmodule NodeTable do
  require Logger

  @lookup_table :node_table_lookup

  def start(node_id) do
    case :ets.whereis(:node_table_lookup) do
      :undefined -> :ets.new(@lookup_table, [:set, :public, :named_table])
    end

    # Create an ETS table with the table name as an atom
    table = :ets.new(:ets_table, [:set, :public])

    true = :ets.insert(@lookup_table, {node_id, table})

    {:ok, table}
  end

  def insert(node_id, key, value) do
    {:ok, table} = get_table(node_id)

    true = :ets.insert(table, {key, value})

    {:ok, :inserted}
  end

  def lookup(node_id, key) do
    {:ok, table} = get_table(node_id)

    case :ets.lookup(table, key) do
      [{_, value}] -> {:ok, value}
      [] -> {:error, :notfound}
    end
  end

  defp get_table(node_id) do
    case :ets.lookup(@lookup_table, node_id) do
      [{_, table}] -> {:ok, table}
      [] -> {:error, :notfound}
    end
  end
end
