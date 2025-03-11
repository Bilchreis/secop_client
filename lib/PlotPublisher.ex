defmodule PlotPublisher do
  use GenServer
  require Logger

  alias MeasBuff


  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        {:via, Registry,
         {Registry.PlotPublisher, {opts[:host], opts[:port], opts[:module], opts[:parameter]}}}
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

  def get_data(parameter_id) do
    [{plt_pub_pid, _value}] = Registry.lookup(Registry.PlotPublisher, parameter_id)
    GenServer.call(plt_pub_pid, :get_data)
  end

  @impl true
  def init(opts) do
    param_id = "#{opts[:host]}:#{opts[:port]}:#{opts[:module]}:#{opts[:parameter]}"

    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host], opts[:port]},
      parameter_id: {opts[:host], opts[:port], opts[:module], opts[:parameter]},
      datainfo: {opts[:datainfo]},
      parameter: opts[:parameter] || %{},
      module: opts[:module],
      pubsub_topic: param_id,
      measbuff: %MeasBuff{}
    }

    Phoenix.PubSub.subscribe(:secop_client_pubsub, state.pubsub_topic)

    Logger.debug("Started Plot publisher for #{state.pubsub_topic}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_data, _from, %{measbuff: measbuff} = state) do
    readings = MeasBuff.get_buffer_list(measbuff)

    {:reply, {:ok, readings}, state}
  end

  @impl true
  def handle_info({:value_update, _pubsub_topic, data_report}, %{measbuff: measbuff} = state) do
    {:noreply, %{state | measbuff: MeasBuff.add_reading(measbuff, data_report)}}
  end
end

defmodule PlotPublisherSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(
      __MODULE__,
      opts,
      name: {:via, Registry, {Registry.PlotPublisherSupervisor, {opts[:host], opts[:port]}}}
    )
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(opts) do
    [{plt_pub_sup_pid, _value}] =
      Registry.lookup(Registry.PlotPublisherSupervisor, {opts[:host], opts[:port]})

    DynamicSupervisor.start_child(plt_pub_sup_pid, {PlotPublisher, opts})
  end

  # Function to terminate all children
  def terminate_all_children(node_id) do
    [{plt_pub_sup_pid, _value}] = Registry.lookup(Registry.PlotPublisherSupervisor, node_id)

    DynamicSupervisor.which_children(plt_pub_sup_pid)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(plt_pub_sup_pid, pid)
    end)
  end
end
