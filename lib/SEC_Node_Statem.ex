defmodule SEC_Node_Statem do
  require Logger
  alias NodeTable
  alias UUID
  alias TcpConnection

  @behaviour :gen_statem

  @initial_state :disconnected

  # Public
  def start_link(opts) do
    :gen_statem.start_link(
      {:via, Registry.SEC_Node_Statem, {opts[:host], opts[:port]}},
      __MODULE__,
      opts,
      []
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl :gen_statem
  def callback_mode, do: :handle_event_function

  def describe(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, :describe)
  end

  def activate(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, :activate)
  end

  def deactivate(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, :deactivate)
  end

  def change(node_id, module, parameter, value) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, {:change, module, parameter, value})
  end

  def execute_command(node_id, module, command, value) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, {:do, module, command, value})
  end

  def execute_command(node_id, module, command) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, {:do, module, command, "null"})
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

    {:ok, @initial_state, state, {:next_event, :internal, :connect}}
  end

  @impl :gen_statem
  def handle_event(:internal, :connect, :disconnected, %{node_id: node_id} = state) do
    case TcpConnection.is_connected(node_id) do
      true -> {:next_state, :connected, state}
      false -> {:keep_state, state, {{:timeout, :reconnect}, 5000, nil}}
    end
  end

  # periodically check if socket is connected
  def handle_event({:timeout, :reconnect}, nil, :disconnected, state) do
    {:keep_state, state, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, :socket_disconnected, machine_state, state)
      when machine_state in [:connected, :initialized] do
    {:next_state, :disconnected, state, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, :socket_connected, :disconnected, state) do
    {:next_state, :connected, state, {:next_event, :internal, :handshake}}
  end

  def handle_event(:internal, :handshake, :connected, %{node_id: node_id,description: description} = state) do
    #TODO IDN
    Logger.info("Initial Describe Message sent")
    TcpConnection.send_message(node_id, ~c"describe .\n")
    receive do
      {:describe, specifier, structure_report} ->
        Logger.info("Description received")
        equipment_id = Map.get(structure_report, "equipment_id")
        case MapDiff.diff(structure_report,description) do
          %{changed: :equal,value: _} ->  updated_state_descr = %{state | description: structure_report, equipment_id: equipment_id}
          _ -> updated_state_descr = %{state | description: structure_report,uuid: UUID.uuid1(), equipment_id: equipment_id}
        end


        return = {:next_state, }
    after
      15000 -> {:reply, :error, state}
    end


  end

  @impl true
  def handle_call(:describe, _from, %{node_id: node_id} = state) do
    Logger.info("Describe Message sent")
    TcpConnection.send_message([:identifier, node_id], ~c"describe .\n")

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
    TcpConnection.send([:identifier, node_id], ~c"activate\n")

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
    TcpConnection.send([:identifier, node_id], ~c"deactivate\n")

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

    TcpConnection.send([:identifier, node_id], String.to_charlist(message))

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
    TcpConnection.send([:identifier, node_id], String.to_charlist(message))

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
