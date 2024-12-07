defmodule TcpConnection do
alias TcpConnection.Buffer

  require Logger


  @behaviour :gen_statem

  @initial_state :disconnected

  ## Public API

  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, [])
  end

  ## Callbacks

  @impl :gen_statem
  def callback_mode, do: :handle_event_function

  @impl :gen_statem
  def init(opts) do
    {:ok,buffer_pid} = Buffer.create()

    state = %{
      host: opts[:host],
      port: opts[:port],
      socket: nil,
      reconnect_backoff: opts[:reconnect_backoff] || 500,
      buffer_pid: buffer_pid
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

  def handle_event(:info, {:tcp, _socket, data}, :connected, %{buffer_pid: buffer_pid} = state) do


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

  def send(pid, data) do
    :gen_statem.call(pid, {:send, data})
  end




  defmodule Buffer do
    @moduledoc "Buffer the data received to parse out statements"


    use GenServer
    require Logger


    @eol <<10>>
    @initial_state ""

    def create do
      GenServer.start_link(__MODULE__, @initial_state)
    end

    def receive(pid \\ __MODULE__, data) do
      GenServer.cast(pid, {:receive, data})
    end

    @impl true
    def init(buffer) do
      {:ok, buffer}
    end

    @impl true
    def handle_cast({:receive, data}, buffer) do
      buffer
      |> append(data)
      |> process
    end

    defp append(buffer, ""), do: buffer
    defp append(buffer, data), do: buffer <> data

    defp process(buffer) do
      case extract(buffer) do
        {:statement, buffer, statement} ->
          Logger.info("message: #{statement}")
          process(buffer)
        {:nothing, buffer} ->
          {:noreply, buffer}
      end
    end

    defp extract(buffer) do
      case String.split(buffer, @eol, parts: 2) do
        [match, rest] -> {:statement, rest, match}
        [rest] -> {:nothing, rest}
      end
    end
  end



end
