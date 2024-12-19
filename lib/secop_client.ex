defmodule SecopClient do
  # alias SecopClient.UdpBroadcaster
  alias NodeDiscover
  alias TcpConnection
  alias Buffer
  alias BufferSupervisor
  alias TcpConnectionSupervisor
  alias SEC_Node_Statem
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.Buffer},
      {Registry, keys: :unique, name: Registry.TcpConnection},
      {Registry, keys: :unique, name: Registry.SEC_Node_Statem},
      {SEC_Node_Supervisor,[]},
      {TcpConnectionSupervisor, []},
      {BufferSupervisor, []},
      {NodeDiscover, &SEC_Node_Supervisor.start_child_from_discovery/3}
    ]

    opts = [strategy: :one_for_one, name: SecopClient.Supervisor]

    Supervisor.start_link(children, opts)



    # Buffer.start_link(buffer_id)

    # [{buffer_pid,_value}] = Registry.lookup(Registry.Buffer,buffer_id)

    # Buffer.receive(buffer_pid,"dscpsdcj\n")

    # {:ok, pid} = TcpConnection.start_link(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 10000)

    # TcpConnection.send(pid,~c"describe .\n")
    # TcpConnection.send(pid,~c"activate\n")

    #node_id = {~c"192.168.178.52", 10800}

    #SEC_Node_Statem.start_link(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 1000)


    #SEC_Node_Supervisor.start_child(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 1000)


    #Process.sleep(1000)

    #SEC_Node_Statem.change(node_id, "massflow_contr1", "target", 20)


    #{:ok, self()}
  end
end
