defmodule SEC_Node_Statem do
  require Logger
  alias NodeTable
  alias UUID
  alias TcpConnection
  alias SecNodePublisherSupervisor

  @behaviour :gen_statem

  @initial_state :disconnected

  # Public
  def start_link(opts) do
    Logger.info("starting secnode")

    :gen_statem.start_link(
      {:via, Registry, {Registry.SEC_Node_Statem, {opts[:host], opts[:port]}}},
      __MODULE__,
      opts,
      []
    )
  end

  def child_spec(opts) do
    %{
      id: {opts[:host], opts[:port]},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl :gen_statem
  def callback_mode, do: :handle_event_function


  def get_state(pid) do
    :gen_statem.call(pid, :get_state)
  end

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

  def read(node_id, module, parameter, value) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, {:read, module, parameter, value})
  end

  def ping(node_id) do
    [{sec_node_pid, _value}] = Registry.lookup(Registry.SEC_Node_Statem, node_id)
    :gen_statem.call(sec_node_pid, :ping)
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
      pubsub_topic: "#{opts[:host]}:#{opts[:port]}",
      equipment_id: nil,
      reconnect_backoff: opts[:reconnect_backoff] || 5000,
      description: nil,
      active: false,
      uuid: UUID.uuid1(),
      error: false
    }

    Logger.info("opening connection")
    TcpConnection.connect_supervised(opts)

    NodeTable.start(state.node_id)

    {:ok, @initial_state, state, {:next_event, :internal, :connect}}
  end

  @impl :gen_statem
  def handle_event(:internal, :connect, :disconnected, %{node_id: node_id} = state) do
    case TcpConnection.is_connected(node_id) do
      true -> {:next_state, :connected, state, {:next_event, :internal, :handshake}}
      false -> {:keep_state, state, {{:timeout, :reconnect}, 5000, nil}}
    end
  end

  # periodically check if socket is connected
  def handle_event({:timeout, :reconnect}, nil, :disconnected, state) do
    {:keep_state, state, {:next_event, :internal, :connect}}
  end

  # Do noting if Connection was already established again
  def handle_event({:timeout, :reconnect}, nil, :initialized, _state) do
    {:keep_state_and_data, []}
  end

  # Do noting if Connection was already established again
  def handle_event({:timeout, :reconnect}, nil, :connected, _state) do
    {:keep_state_and_data, []}
  end

  def handle_event(:info, :socket_disconnected, machine_state, state)
      when machine_state in [:connected, :initialized] do
    {:next_state, :disconnected, state, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, :socket_connected, :disconnected, state) do
    {:next_state, :connected, state, {:next_event, :internal, :handshake}}
  end

  def handle_event(:info, :socket_connected, :connected, _state) do
    {:keep_state_and_data, []}
  end

  def handle_event(:info, :socket_connected, :initialized, _state) do
    {:keep_state_and_data, []}
  end

  def handle_event({:call, from}, message, :disconnected, _state) do
    Logger.warning("Node call while disconnected: #{elem(message, 0)}")
    {:keep_state_and_data, {:reply, from, {:error, :disconnected}}}
  end

  def handle_event({:call, from}, message, :connected, _state) do
    Logger.warning("Node call before initialization: #{elem(message, 0)}")
    {:keep_state_and_data, {:reply, from, {:error, :uninitialized}}}
  end

  def handle_event(
        :internal,
        :handshake,
        :connected,
        %{node_id: node_id, description: description} = state
      ) do
    # TODO IDN

    Logger.info("Initial Describe Message sent")

    case send_describe_message(node_id) do
      {:ok, _specifier, parsed_description} ->
        equipment_id = parsed_description[:node_properties][:equipment_id]

        case MapDiff.diff(parsed_description, description) do
          # Notihng changed, probably just a network disconnect
          %{changed: :equal, value: _} ->
            Logger.info("Descriptive data constant --> connected & initialized")
            {:next_state, :initialized, state, {:next_event, :internal, :activate}}

          # Description changed update uuid, equipment_id and description
          _ ->
            Logger.info("Descriptive data changed issuing new uuid --> connected & initialized")

            {:ok, empty_values_map} = SECoP_Parser.get_empty_values_map(parsed_description)


            case Registry.lookup(Registry.SecNodePublisher, state.node_id) do
              [] ->
                SecNodePublisherSupervisor.start_child(
                  host: state.host,
                  port: state.port,
                  values_map: empty_values_map
                )

              [{publisher_pid, _value}] ->
                SecNodePublisher.set_values_map(publisher_pid, empty_values_map)
            end

            updated_state_descr = %{
              state
              | description: parsed_description,
                uuid: UUID.uuid1(),
                equipment_id: equipment_id
            }

            {:next_state, :initialized, updated_state_descr, {:next_event, :internal, :activate}}
        end

      {:error, :timeout} ->
        Logger.warning(
          "NO answer on describe message for #{elem(node_id, 0)}:#{elem(node_id, 1)}, going into ERROR state"
        )

        {:next_state, :could_not_initialize, state}

        # TODO Handle error reply
    end
  end

  def handle_event(:internal, :activate, :initialized, %{node_id: node_id} = state) do
    case send_activate_message(node_id) do
      {:ok, :active} ->
        updated_state = %{state | active: true}
        {:keep_state, updated_state}

      # TODO handle error_reply
      {:error, :timeout} ->
        {:keep_state_and_data, []}
    end
  end


  def handle_event({:call, from}, :get_state, state_name, state) when state_name in [:initialized, :connected, :disconnected] do
    {:keep_state_and_data, {:reply, from, {:ok, state}}}
  end



  def handle_event(
        {:call, from},
        :describe,
        :initialized,
        %{node_id: node_id, description: description} = state
      ) do
    Logger.info("Describe Message sent")

    case send_describe_message(node_id) do
      {:ok, _specifier, parsed_description} ->
        equipment_id = parsed_description[:node_properties][:equipment_id]

        case MapDiff.diff(parsed_description, description) do
          # Notihng changed, probably just a network disconnect
          %{changed: :equal, value: _} ->
            Logger.info("Descriptive data constant")
            {:keep_state_and_data, {:reply, from, {:describing, parsed_description}}}

          # Description changed update uuid, equipment_id and description
          _ ->
            Logger.info("Descriptive data changed issuing new uuid")

            updated_state_descr = %{
              state
              | description: parsed_description,
                uuid: UUID.uuid1(),
                equipment_id: equipment_id
            }

            {:keep_state, updated_state_descr, {:reply, from, {:describing, parsed_description}}}
        end

      {:error, :timeout} ->
        Logger.warning(
          "NO answer on describe message for #{elem(node_id, 0)}:#{elem(node_id, 1)}, going into ERROR state"
        )

        {:keep_state_and_data, {:reply, from, {:error, :timeout}}}

        # TODO Handle error reply
    end
  end

  def handle_event({:call, from}, :activate, :initialized, %{node_id: node_id} = state) do
    Logger.info("Activate Message sent")

    case send_activate_message(node_id) do
      {:ok, :active} ->
        updated_state = %{state | active: true}
        {:keep_state, updated_state, {:reply, from, {:active}}}

      # TODO handle error_reply
      {:error, :timeout} ->
        {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event({:call, from}, :deactivate, :initialized, %{node_id: node_id} = state) do
    Logger.info("Deactivate Message sent")
    TcpConnection.send_message(node_id, ~c"deactivate\n")

    receive do
      {:inactive} ->
        Logger.info("Node Inactive")
        updated_state = %{state | active: false}
        {:keep_state, updated_state, {:reply, from, {:inactive}}}
    after
      5000 -> {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event(
        {:call, from},
        {:change, module, parameter, value},
        :initialized,
        %{node_id: node_id} = _state
      ) do
    message = "change #{module}:#{parameter} #{value}\n"

    Logger.info("Change Message '#{String.trim_trailing(message)}' sent")

    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:changed, r_module, r_parameter, data_report} ->
        Logger.info("Value of #{r_module}:#{r_module} changed to #{Jason.encode!(data_report)}")
        {:keep_state_and_data, {:reply, from, {:changed, r_module, r_parameter, data_report}}}
    after
      5000 -> {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event(
        {:call, from},
        {:do, module, command, value},
        :initialized,
        %{node_id: node_id} = _state
      ) do
    message = "do #{module}:#{command} #{value}\n"

    Logger.info("Do Message '#{String.trim_trailing(message)}' sent")
    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:done, r_module, r_command, data_report} ->
        Logger.info(
          "Command #{module}:#{command} executed and returned: #{Jason.encode!(data_report)}"
        )

        {:keep_state_and_data, {:reply, from, {:changed, r_module, r_command, data_report}}}
    after
      5000 -> {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event(
        {:call, from},
        {:read, module, parameter, value},
        :initialized,
        %{node_id: node_id} = _state
      ) do
    message = "read #{module}:#{parameter} #{value}\n"

    Logger.info("Read Message '#{String.trim_trailing(message)}' sent")
    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:reply, r_module, r_parameter, data_report} ->
        Logger.info(
          "Read request #{module}:#{parameter} sent and returned: #{Jason.encode!(data_report)}"
        )

        {:keep_state_and_data, {:reply, from, {:reply, r_module, r_parameter, data_report}}}
    after
      5000 -> {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event({:call, from}, :ping, :initialized, %{node_id: node_id} = _state) do
    # generate random id
    id = Enum.random(1..100_000)

    message = "ping #{id}\n"

    Logger.info("Ping Message '#{String.trim_trailing(message)}' sent")
    TcpConnection.send_message(node_id, String.to_charlist(message))

    receive do
      {:pong, id, data} ->
        Logger.info("Corresponding Pong received: #{Jason.encode!(data)}")
        {:keep_state_and_data, {:reply, from, {:pong, id, data}}}
    after
      5000 -> {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
    end
  end

  def handle_event(:info, {:active}, :initialized, state) do
    Logger.warning("received async ACTIVE message")
    updated_state = %{state | active: true}
    {:keep_state, updated_state}
  end

  def handle_event(:info, {:inactive}, :initialized, state) do
    Logger.warning("received async INACTIVE message")
    updated_state = %{state | active: false}
    {:keep_state, updated_state}
  end

  def handle_event(:info, {:pong, id, data}, :initialized, _state) do
    Logger.warning("received async PONG message id:#{id}, data:#{data}")
    {:keep_state_and_data}
  end

  def handle_event(
        :info,
        {:describe, _specifier, parsed_description},
        :initialized,
        %{description: description} = state
      ) do
    equipment_id = parsed_description[:node_properties][:equipment_id]

    case MapDiff.diff(parsed_description, description) do
      # Notihng changed, probably just a network disconnect
      %{changed: :equal, value: _} ->
        Logger.warning("received async Description: data constant")
        {:keep_state_and_data}

      # Description changed update uuid, equipment_id and description
      _ ->
        Logger.warning("received async Description: data changed issuing new uuid")

        updated_state_descr = %{
          state
          | description: parsed_description,
            uuid: UUID.uuid1(),
            equipment_id: equipment_id
        }

        {:keep_state, updated_state_descr}
    end
  end

  def handle_event(:info, {:done, module, command, data_report}, :initialized, _state) do
    Logger.warning("received async DONE message #{module}:#{command} data: #{data_report}")
    {:keep_state_and_data}
  end

  def handle_event(:info, {:reply, module, parameter, data_report}, :initialized, _state) do
    Logger.warning("received async REPLY message #{module}:#{parameter} data: #{data_report}")
    {:keep_state_and_data}
  end

  def handle_event(:info, {:changed, module, parameter, data_report}, :initialized, _state) do
    Logger.warning("received async CHANGED message #{module}:#{parameter} data: #{data_report}")
    {:keep_state_and_data}
  end

  defp send_describe_message(node_id) do
    TcpConnection.send_message(node_id, ~c"describe .\n")

    receive do
      {:describe, specifier, parsed_description} ->
        Logger.info("Description received")
        {:ok, specifier, parsed_description}
        # TODO ERROR reply
    after
      15000 -> {:error, :timeout}
    end
  end

  defp send_activate_message(node_id) do
    TcpConnection.send_message(node_id, ~c"activate\n")

    receive do
      {:active} ->
        Logger.info("Node Activated")
        {:ok, :active}

        # TODO ERROR reply
    after
      15000 -> {:error, :timeout}
    end
  end
end

defmodule SEC_Node_Supervisor do
  # Automatically defines child_spec/1
  alias Jason
  use DynamicSupervisor
  @reconnect_backoff 5000

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(opts) do
    DynamicSupervisor.start_child(__MODULE__, {SEC_Node_Statem, opts})
  end

  def start_child_from_discovery(ip, _port, discovery_message) do
    discover_map = Jason.decode!(discovery_message)

    chl_ip = ip |> Tuple.to_list() |> Enum.join(".") |> String.to_charlist()

    node_port = Map.get(discover_map, "port")

    opts = %{
      host: chl_ip,
      port: node_port,
      reconnect_backoff: @reconnect_backoff
    }

    case Registry.lookup(Registry.SEC_Node_Statem, {chl_ip, node_port}) do
      [] -> DynamicSupervisor.start_child(__MODULE__, {SEC_Node_Statem, opts})
      _ -> {:ok, :node_already_running}
    end
  end
end

defmodule NodeTable do
  require Logger

  @lookup_table :node_table_lookup

  def start(node_id) do
    case :ets.whereis(:node_table_lookup) do
      :undefined -> :ets.new(@lookup_table, [:set, :public, :named_table])
      _ -> {:ok}
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
