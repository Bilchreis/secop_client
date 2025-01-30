defmodule Plot_Publisher do
  use GenServer
  require Logger

  @max_duration 30*60*60
  @max_buffer_len 200
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
    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host], opts[:port]},
      parameter_id: {opts[:host], opts[:port], opts[:module], opts[:parameter]},
      datainfo: {opts[:datainfo]},
      parameter: opts[:parameter] || %{},
      module: opts[:module],
      pubsub_topic: "#{opts[:host]}:#{opts[:port]}:#{opts[:module]}:#{opts[:parameter]}",
      buffer: :queue.new(),
      buff_len: 0
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
  def handle_info(:work, state) do

    #Logger.info("Publish SVG")
    #IO.inspect(:queue.to_list(state.buffer))


    # Reschedule once more
    schedule_collection()

    {:noreply, state}
  end

  @impl true
  def handle_info({:value_update, pubsub_topic, data_report}, %{buffer: buffer, buff_len: buff_len} = state) do
    [value, qualifiers] = data_report

    {buffer, buff_len} = case qualifiers do
      %{t: timestamp} ->
        buffer =  :queue.in({timestamp, value},buffer)

        buff_len = buff_len + 1

        {:value,{t_peek, _v_peek}} = :queue.peek(buffer)

        tdiff =   timestamp - t_peek

        {buffer,buff_len} = cond do

          buff_len > @max_buffer_len -> remove_reading(buffer,buff_len)

          tdiff > @max_duration ->  remove_reading(buffer,buff_len)

          true -> {buffer,buff_len}

        end
        {buffer, buff_len}

      _ -> {buffer, buff_len}

    end


    {:noreply,%{state | buffer: buffer, buff_len: buff_len}}
  end

  def remove_reading(buffer, buff_len) do
    {{:value,_item},buffer} = :queue.out(buffer)
    buff_len = buff_len - 1
    {buffer,buff_len}
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
