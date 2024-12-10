defmodule SECoP_Parser do
  require Logger

  alias Jason

  def parse(message) do
    split_message = String.trim(message) |> String.split(" ", parts: 3)

    # Handle Error Reports:
    if length(split_message) == 3 and String.starts_with?(hd(split_message), "error_") do
      [error_message, specifier, data] = split_message
      Logger.error("Error message received: #{error_message}, specifier: #{specifier}, data: #{data}")
    else
      # Handle all Normal SECoP Messages:
      case split_message do
        ["update", specifier, data]     -> update(specifier, data)
        ["describing", specifier, data] -> describe(specifier, data)
        ["inactive"]                    -> inactive()
        ["pong", id, data]              -> pong(id, data)
        ["active"]                      -> active()
        ["reply", specifier, data]      -> reply(specifier, data)
        ["changed", specifier, data]    -> changed(specifier, data)
        ["done", specifier, data]       -> done(specifier, data)
        _                               -> Logger.warning("Unknown message received: #{message}")
      end
    end
  end

  def update(specifier, data) do
    Logger.info("Update message received. Specifier: #{specifier}, Data: #{data}")
    # Additional processing logic here
  end

  def describe(specifier, data) do
    Logger.info("Describe message received. Specifier: #{specifier}, Data: #{data}")
    # Additional processing logic here
  end

  def inactive() do
    Logger.info("Deactivated update messages received.")
    # Additional processing logic here
  end

  def pong(id, data) do
    Logger.info("Pong received. ID: #{id}, Data: #{data}")
    # Additional processing logic here
  end

  def active() do
    Logger.info("Active message received.")
    # Additional processing logic here
  end

  def reply(specifier, data) do
    Logger.info("Read reply received. Specifier: #{specifier}, Data: #{data}")
    # Additional processing logic here
  end

  def changed(specifier, data) do
    Logger.info("Parameter successfully changed. Specifier: #{specifier}, Data: #{data}")
    # Additional processing logic here
  end

  def done(specifier, data) do
    Logger.info("Command executed. Specifier: #{specifier}, Data: #{data}")
    # Additional processing logic here
  end
end
