defmodule SecopClient do
  #alias SecopClient.UdpBroadcaster
  alias NodeDiscover
  use Application
  def start(_type, _args) do
    children = [
      {NodeDiscover,fn  _ip, _port, message-> IO.puts("node Discovered!!! #{message}")end }
    ]



    opts = [strategy: :one_for_one, name: NodeDiscover.Supervisor]

    Supervisor.start_link(children, opts)
  end


end
