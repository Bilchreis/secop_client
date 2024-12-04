defmodule SocketStruct do
  defstruct socket: nil, callback: nil

end

defmodule NodeDiscover do
  use GenServer
  alias SocketStruct
  @message "{\"SECoP\": \"discover\"}"
  @broadcast_address {255, 255, 255, 255} # Broadcast address
  @port 10767
  @interval 5000
  require Logger

  # Starts the GenServer with a given UDP port and callback function
  def start_link(callback_function) do
    GenServer.start_link(
      __MODULE__,
      %SocketStruct{socket: nil,callback: callback_function},
       name: __MODULE__)
  end

  @impl true
  def init(socketstruct) do
    # Open a UDP socket
    {:ok, socket} = :gen_udp.open(0, [{:broadcast, true}, {:ip, {0, 0, 0, 0}},{:active, true}])

    # Send the message to the broadcast address and port
    :gen_udp.send(socket, @broadcast_address, @port, @message)
    schedule_scan()

    {:ok, %SocketStruct{socket: socket, callback: socketstruct.callback}}
  end


  def scan(pid) do
    GenServer.cast(pid, :scan)

  end

  @impl true
  def handle_cast(:scan, socketstruct) do
      # Send the message to the broadcast address and port
      send_discover(socketstruct)
    {:noreply, socketstruct}
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, message}, socketstruct) do
    # Log received message
    #Logger.info("Received UDP message from #{inspect(ip)}:#{port} -> #{message}")

    # Invoke the callback function
    socketstruct.callback.(ip, port, message)
    #IO.puts(message)

    {:noreply, socketstruct}
  end


  @impl true
  def handle_info(:work, socketstruct) do
    # Do the desired work here
    send_discover(socketstruct)

    # Reschedule once more
    schedule_scan()

    {:noreply, socketstruct}
  end

  defp schedule_scan do
    # We schedule the work to happen in 2 hours (written in milliseconds).
    # Alternatively, one might write :timer.hours(2)
    Process.send_after(self(), :work, @interval)
  end

  @impl true
  def terminate(_reason, %{socket: socket}) do
    # Close the socket on termination
    :gen_udp.close(socket)
    :ok
  end

  defp send_discover(socketstruct) do
    :gen_udp.send(socketstruct.socket, @broadcast_address, @port, @message)
  end


end
