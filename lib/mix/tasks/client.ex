defmodule Mix.Tasks.Client do
  use Mix.Task
  alias SecopClient
  alias SEC_Node_Supervisor


  @shortdoc "Starts the SecopClient application and runs indefinitely"

  def run(_args) do
    Mix.Task.run("app.start")

    Process.sleep(3000)


    node_map = SEC_Node_Supervisor.get_active_nodes()

    IO.inspect(node_map, label: "Active nodes")

    #all_entries = Registry.select(Registry.PlotPublisher,[{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    #IO.inspect(all_entries, label: "All entries (key, PID pairs)")

    #Registry.PlotPublisher

    #parameter_id = {~c"192.168.178.52", 10800,:massflow_contr1,:value}

    #IO.inspect(PlotPublisher.get_data(parameter_id))



    # Keep the application running indefinitely
    :timer.sleep(:infinity)
  end
end
