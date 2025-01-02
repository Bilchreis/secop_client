defmodule SecNodePublisher do
  use GenServer
  require Logger

  @interval 1000

  ## client side

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: {:via, Registry, {Registry.SecNodePublisher, {opts[:host], opts[:port]}}}
    )
  end

  def set_values_map(node_id, values_map) do
    [{publisher_pid, _value}] = Registry.lookup(Registry.SecNodePublisher, node_id)
    GenServer.call(publisher_pid, {:set_values_map, values_map})
  end

  ## Server side

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def init(opts) do
    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host], opts[:port]},
      values_map: opts[:values_map] || %{},
      pubsub_topic: "#{opts[:host]}:#{opts[:port]}"
    }

    Logger.info("Started publisher for #{state.pubsub_topic}")

    schedule_collection()

    {:ok, state}
  end

  @impl true
  def handle_call({:set_values_map, values_map}, _from, state) do
    {:reply, {:ok}, %{state | values_map: values_map}}
  end

  @impl true
  def handle_info(:work, state) do
    Logger.debug("Sheduled parameter value collection for #{state.pubsub_topic}")

    new_state =
      if map_size(state.values_map) == 0 do
        Logger.warning("No parameters to collect for #{state.pubsub_topic}")
        state
      else
        collect(state)
      end

    # Reschedule once more
    schedule_collection()

    {:noreply, new_state}
  end

  defp schedule_collection do
    # We schedule the work to happen in 2 hours (written in milliseconds).
    # Alternatively, one might write :timer.hours(2)
    Process.send_after(self(), :work, @interval)
  end

  defp collect(state) do
      new_values_map =
      Enum.reduce(state.values_map, %{}, fn {module, parameters}, acc ->
        # acc is the accumulator for the outer Enum.reduce, which accumulates the updated map
        updated_parameters =
          Enum.reduce(parameters, %{}, fn {parameter, _value}, param_acc ->
            # param_acc is the accumulator for the inner Enum.reduce, which accumulates the updated parameters
            case NodeTable.lookup(state.node_id, {:data_report, module, parameter}) do
              {:ok, new_value} ->
                Map.put(param_acc, parameter, new_value)

              {:error, _reason} ->
                param_acc
            end
          end)

        Map.put(acc, module, updated_parameters)
      end)

    new_state = %{state | values_map: new_values_map}
    Phoenix.PubSub.broadcast(
      :secop_parameter_pubsub,
      state.pubsub_topic,
      {:values_map, state.pubsub_topic, new_values_map}
    )

    new_state
  end
end

defmodule SecNodePublisherSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(opts) do
    DynamicSupervisor.start_child(__MODULE__, {SecNodePublisher, opts})
  end
end
