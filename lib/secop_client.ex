defmodule SecopClient do
  #alias SecopClient.UdpBroadcaster
  alias NodeDiscover
  alias ActiveNodeList
  use Application
  def start(_type, _args) do
    children = [
      {ActiveNodeList,%{}},
      {NodeDiscover,&ActiveNodeList.add_node_from_discovery/3}
    ]



    opts = [strategy: :one_for_one, name: NodeDiscover.Supervisor]

    Supervisor.start_link(children, opts)
  end


end
