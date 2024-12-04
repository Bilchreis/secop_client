defmodule ActiveNodeList do
  use GenServer

  def start_link(nodelist) do
    GenServer.start_link( __MODULE__,nodelist,name: __MODULE__)
  end





  init(nodelist) do
    {:ok,nodelist}
  end

end
