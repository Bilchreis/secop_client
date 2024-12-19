defmodule Mix.Tasks.StartClient do
  use Mix.Task

  @shortdoc "Starts the SecopClient application and runs indefinitely"

  def run(_args) do
    Mix.Task.run("app.start")

    # Keep the application running indefinitely
    :timer.sleep(:infinity)
  end
end
