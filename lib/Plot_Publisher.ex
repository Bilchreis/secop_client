defmodule Plot_Publisher do
  use GenServer
  require Logger

  alias MeasBuff
  alias Contex.Dataset
  alias Contex.LinePlot
  alias Contex.Plot
  alias Contex.Sparkline


  @interval 1000



  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        {:via, Registry,
         {Registry.SecNodePublisher, {opts[:host], opts[:port], opts[:module], opts[:parameter]}}}
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
      plot_publish_topic: "plot",
      spark_publish_topic: "spark",
      measbuff: %MeasBuff{}

    }

    Phoenix.PubSub.subscribe(:secop_client_pubsub, state.pubsub_topic)

    schedule_collection()

    Logger.debug("Started Plot publisher for #{state.pubsub_topic}")

    {:ok, state}
  end

  defp schedule_collection do
    # We schedule the work to happen in 2 hours (written in milliseconds).
    # Alternatively, one might write :timer.hours(2)
    Process.send_after(self(), :work, @interval)
  end


  @impl true
  def handle_info(:work, %{measbuff: measbuff} = state) do



    readings = MeasBuff.get_buffer_list(measbuff)
    readings_spark = MeasBuff.get_spark_list(measbuff)

    if readings != [] do

      ds = Dataset.new(readings,["x","t"])

      line_plot = LinePlot.new(ds)

      plot = Plot.new(600, 400, line_plot)
      |> Plot.plot_options(%{legend_setting: :legend_right})
      |> Plot.titles("#{state.parameter}", "With a fancy subtitle")

      {:safe,svg} = Plot.to_svg(plot)

      host      = state.host
      port      = state.port
      module    = state.module
      parameter = state.parameter


      Phoenix.PubSub.broadcast(:secop_client_pubsub, state.plot_publish_topic,{host,port,module,parameter,{:plot, svg}})


    if readings_spark != [] do
      {:safe, [svg] } =  Sparkline.new(readings_spark) |> Sparkline.colours("#fad48e", "#ff9838")
      |> Sparkline.draw()


      Phoenix.PubSub.broadcast(:secop_client_pubsub, state.spark_publish_topic,{host,port,module,parameter,{:spark, svg}})

    end

    end


    # Reschedule once more
    schedule_collection()

    {:noreply, state}
  end

  @impl true
  def handle_info({:value_update, _pubsub_topic, data_report}, %{measbuff: measbuff} = state) do
    {:noreply,%{state | measbuff: MeasBuff.add_reading(measbuff,data_report)}}
  end



end


defmodule Plot_PublisherSupervisor do
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
    [{plt_pub_sup_pid, _value}] = Registry.lookup(Registry.PlotPublisherSupervisor, {opts[:host], opts[:port]})
    DynamicSupervisor.start_child(plt_pub_sup_pid, {Plot_Publisher, opts})
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
