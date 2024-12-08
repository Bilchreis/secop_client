defmodule SecopClient do
  #alias SecopClient.UdpBroadcaster
  alias NodeDiscover
  alias ActiveNodeList
  alias TcpConnection
  alias BufferSupervisor
  use Application
  def start(_type, _args) do
    children = [
      {ActiveNodeList,%{}},
      {NodeDiscover,&ActiveNodeList.add_node_from_discovery/3},
      {DynamicSupervisor, strategy: :one_for_one, name: ConnectionSupervisor}
    ]



    opts = [strategy: :one_for_one, name: SecopClient.Supervisor]

    Supervisor.start_link(children, opts)

    {:ok, pid} = TcpConnection.start_link(host: ~c"127.0.0.1", port: 10800, reconnect_backoff: 10000)


    TcpConnection.send(pid,~c"describe .\n")
    TcpConnection.send(pid,~c"activate\n")

    Process.sleep(:infinity)

    {:ok,self()}
  end


end
