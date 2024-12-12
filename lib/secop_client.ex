defmodule SecopClient do
  # alias SecopClient.UdpBroadcaster
  alias NodeDiscover
  alias ActiveNodeList
  alias TcpConnection
  alias Buffer
  alias BufferSupervisor
  alias TcpConnectionSupervisor
  alias SEC_Node
  use Application

  def start(_type, _args) do
    children = [
      {ActiveNodeList, %{}},
      {NodeDiscover, &ActiveNodeList.add_node_from_discovery/3},
      {DynamicSupervisor, strategy: :one_for_one, name: ConnectionSupervisor},
      {Registry, keys: :unique, name: Registry.Buffer},
      {Registry, keys: :unique, name: Registry.TcpConnection},
      {Registry, keys: :unique, name: Registry.SEC_Node},
      {Registry, keys: :unique, name: Registry.SEC_Node_Statem},
      {TcpConnectionSupervisor, []},
      {BufferSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: SecopClient.Supervisor]

    Supervisor.start_link(children, opts)

    # Buffer.start_link(buffer_id)

    # [{buffer_pid,_value}] = Registry.lookup(Registry.Buffer,buffer_id)

    # Buffer.receive(buffer_pid,"dscpsdcj\n")

    # {:ok, pid} = TcpConnection.start_link(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 10000)

    # TcpConnection.send(pid,~c"describe .\n")
    # TcpConnection.send(pid,~c"activate\n")

    node_id = {~c"127.0.0.1", 10800}

    SEC_Node.start_link(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 1000)

    SEC_Node.describe(node_id)

    SEC_Node.activate(node_id)

    SEC_Node.deactivate(node_id)

    SEC_Node.change(node_id, "backpressure_contr1", "target", 30)

    SEC_Node.execute_command(node_id, "backpressure_contr1", "stop")

    Process.sleep(:infinity)

    {:ok, self()}
  end
end
