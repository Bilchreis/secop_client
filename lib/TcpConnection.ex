defmodule TcpConnection do

  alias Buffer
  alias BufferSupervisor

  require Logger


  @behaviour :gen_statem

  @initial_state :disconnected

  ## Public API

  def connect_supervised(opts) do
    buffer_id = {opts[:host], opts[:port]}

    BufferSupervisor.start_child(buffer_id)
    TcpConnectionSupervisor.start_child(opts)
  end

  def start_link(opts) do
    :gen_statem.start_link({:via, Registry, {Registry.TcpConnection, {opts[:host], opts[:port]}}},__MODULE__, opts, [])
  end

  ## Callbacks

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

  @impl :gen_statem
  def init(opts) do




    state = %{
      host: opts[:host],
      port: opts[:port],
      socket: nil,
      reconnect_backoff: opts[:reconnect_backoff] || 500,

    }

    {:ok, @initial_state, state, {:next_event, :internal, :connect}}
  end

  @impl :gen_statem
  def handle_event(:internal, :connect, :disconnected, state) do
    case :gen_tcp.connect(state.host, state.port, [:binary, active: true]) do
      {:ok, socket} ->
        Logger.info("Connected to #{state.host}:#{state.port}")
        {:next_state, :connected, %{state | socket: socket}}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:keep_state, state, {{:timeout, :reconnect}, state.reconnect_backoff, nil}}
    end
  end

  def handle_event({:timeout, :reconnect}, nil, :disconnected, state) do
    {:keep_state, state, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, {:tcp, _socket, data}, :connected, %{host: host,port: port} = state) do

    [{buffer_pid,_value}] = Registry.lookup(Registry.Buffer,{host,port})
    Buffer.receive(buffer_pid,data)

    # Update the buffer with remaining data
    {:keep_state, state}
  end

  def handle_event(:info, {:tcp_closed, _socket}, :connected, state) do
    Logger.warning("Connection closed by server")
    {:next_state, :disconnected, %{state | socket: nil}, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, {:tcp_error, _socket, reason}, :connected, state) do
    Logger.error("TCP error: #{inspect(reason)}")
    {:next_state, :disconnected, %{state | socket: nil}, {:next_event, :internal, :connect}}
  end

  def handle_event({:call, from}, {:send, data}, :connected, state) do
    Logger.info("sending data: #{data}")
    case :gen_tcp.send(state.socket, data) do
      :ok ->
        Logger.info("received reply")
        :gen_statem.reply(from, :ok)

      {:error, reason} -> :gen_statem.reply(from, {:error, reason})
    end

    {:keep_state, state}
  end

  ## Helpers

  def send(identifier, data) do
   conn_pid =
     case identifier do
      [:identifier, {host,port}] -> Registry.lookup(Registry.TcpConnection,{host,port}) |> List.last()|> elem(0)
      [:pid, pid] -> pid
    end
    :gen_statem.call(conn_pid, {:send, data})
  end




end



defmodule BufferSupervisor do


  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(buffer_identifier) do
    DynamicSupervisor.start_child(__MODULE__,{Buffer,buffer_identifier})
  end
end


defmodule TcpConnectionSupervisor do
  # Automatically defines child_spec/1
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(opts) do
    DynamicSupervisor.start_child(__MODULE__,{TcpConnection,opts})
  end
end




defmodule Buffer do
  @moduledoc "Buffer the data received to parse out statements"


  use GenServer
  require Logger
  alias SECoP_Parser


  @eol <<10>>
  @initial_state ""

  def start_link(buffer_identifier \\ nil) do
    state = %{
      buffer: @initial_state,
      node_id: buffer_identifier
  }

    GenServer.start_link(__MODULE__, state,name: {:via, Registry, {Registry.Buffer, buffer_identifier}})
  end

  def receive(pid \\ __MODULE__, data) do
    GenServer.cast(pid, {:receive, data})
  end

  @impl true
  def init(buffer) do
    {:ok, buffer}
  end

  @impl true
  def handle_cast({:receive, data}, %{buffer: buffer} = state) do
    updated_buffer = buffer  |> append(data) |> process

    {:noreply, %{state | :buffer => updated_buffer}}

  end

  defp append(buffer, ""), do: buffer
  defp append(buffer, data), do: buffer <> data

  defp process(buffer) do
    case extract(buffer) do
      {:statement, buffer, statement} ->
        SECoP_Parser.parse(statement)
        process(buffer)
      {:nothing, buffer} ->
        buffer
    end
  end

  defp extract(buffer) do
    case String.split(buffer, @eol, parts: 2) do
      [match, rest] -> {:statement, rest, match}
      [rest] -> {:nothing, rest}
    end
  end
end
