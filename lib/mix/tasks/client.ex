defmodule Mix.Tasks.Client do
  use Mix.Task
  alias SecopClient

  @shortdoc "Starts the SecopClient application and runs indefinitely"

  def run(_args) do
    Mix.Task.run("app.start")

    # Process.sleep(1000)

    # IO.inspect(SecopClient.get_active_nodes())

    # Keep the application running indefinitely
    :timer.sleep(:infinity)
  end
end
