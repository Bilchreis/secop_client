defmodule SEC_Node do
   use GenServer
   require Logger

   alias TcpConnection
   #Public
   def start_link(opts)do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: {:via, Registry, {Registry.SEC_Node, {opts[:host], opts[:port]}}}
      )
   end


   def describe(node_id) do
    [{tcp_conn_pid,_value}] = Registry.lookup(Registry.SEC_Node,node_id)
    GenServer.call(tcp_conn_pid,:describe)

   end

   def activate(node_id) do
    [{tcp_conn_pid,_value}] = Registry.lookup(Registry.SEC_Node,node_id)
    GenServer.call(tcp_conn_pid,:activate)

   end



   #callbacks
   @impl true
   def init(opts) do
    state = %{
      host: opts[:host],
      port: opts[:port],
      node_id: {opts[:host],opts[:port]},
      equipment_id: nil,
      reconnect_backoff: opts[:reconnect_backoff] || 5000,

    }
    TcpConnection.connect_supervised(opts)




     {:ok, state}
   end

   @impl true
   def handle_call(:describe, _from,%{node_id: node_id}  =state) do
    TcpConnection.send([:identifier, node_id],~c"describe .\n")
    Logger.info("describing #{state.host}:#{state.port}")
    to_caller = "describing"

    {:reply, to_caller, state}
   end

   @impl true
   def handle_call(:activate, _from,%{node_id: node_id}  =state) do
    TcpConnection.send([:identifier, node_id],~c"activate\n")
    Logger.info("activating #{state.host}:#{state.port}")
    to_caller = "activating"

    {:reply, to_caller, state}
   end


end
