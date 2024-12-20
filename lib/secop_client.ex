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
      {Phoenix.PubSub, name: :secop_parameter_pubsub},
      {Registry, keys: :unique, name: Registry.Buffer},
      {Registry, keys: :unique, name: Registry.TcpConnection},
      {Registry, keys: :unique, name: Registry.SEC_Node_Statem},
      {Registry, keys: :unique, name: Registry.SecNodePublisher},
      {SEC_Node_Supervisor, []},
      {TcpConnectionSupervisor, []},
      {BufferSupervisor, []},
      {SecNodePublisherSupervisor, []},
      {NodeDiscover, &SEC_Node_Supervisor.start_child_from_discovery/3}
    ]

    opts = [strategy: :one_for_one, name: SecopClient.Supervisor]

    Supervisor.start_link(children, opts)
  end

  def get_active_nodes() do
    Supervisor.which_children(SEC_Node_Supervisor) |>
    Enum.reduce(%{}, fn {_id, pid, _type, _module}, acc ->
      case SEC_Node_Statem.get_state(pid) do
        {:ok, state} ->
          Map.put(acc, pid, state)
        _ ->
          acc
      end
    end)
  end
end
