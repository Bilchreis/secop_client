defmodule Plot_Publisher do

  use GenServer
  require Logger

  @max_duration
  @max_buffer_len


  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: {:via, Registry, {Registry.SecNodePublisher, {opts[:host], opts[:port],opts[:module],opts[:parameter]}}}
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

  @impl true
  def init(opts) do
    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host], opts[:port]},
      parameter_id: {opts[:host], opts[:port],opts[:module],opts[:parameter]},
      parameter: opts[:parameter] || %{},
      module: opts[:module],
      pubsub_topic: "#{opts[:host]}:#{opts[:port]}:#{opts[:module]}:#{opts[:parameter]}",
      buffer: []


    }

    Phoenix.PubSub.subscribe(:secop_client_pubsub, state.pubsub_topic)

    Logger.debug("Started Plot publisher for #{state.pubsub_topic}")

    {:ok, state}
  end



  def handle_info({:vlaue_update, pubsub_topic, data}, state) do
    state
  end









end
