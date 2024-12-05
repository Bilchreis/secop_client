

defmodule ActiveNodeList do
  use GenServer
  alias Jason

  @spec start_link(map()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(nodemap) do
    GenServer.start_link( __MODULE__,nodemap,name: __MODULE__)
  end


  def add_node(ip,port,equipment_id) do
    GenServer.cast(__MODULE__,{:add_node,ip,port,equipment_id})
  end


  def add_node_from_discovery(ip,port,message) do
     GenServer.cast(__MODULE__,{:add_node_from_discovery,ip,port,message})
  end



  @impl true
  def handle_cast({:add_node,ip,port,equipment_id}, nodemap) do
    updated_nodemap = Map.put(nodemap,{ip,port},equipment_id)
    {:noreply, updated_nodemap}
  end

  @impl true
  def handle_cast({:add_node_from_discovery,ip,port,message}, nodemap) do
    discover_map =  Jason.decode!(message)

    equipment_id = Map.get(discover_map,"equipment_id")

    updated_nodemap = Map.put(nodemap,{ip,port},equipment_id)

    {:noreply, updated_nodemap}
  end

  @impl true
  @spec init(map()) :: {:ok, any()}
  def init(nodemap) do
    {:ok,nodemap}
  end

end
