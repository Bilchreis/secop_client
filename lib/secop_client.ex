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

  end
end
