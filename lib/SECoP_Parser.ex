defmodule SECoP_Parser do
  require Logger
  require NodeTable

  alias Jason

  def parse(node_id, message) do
    split_message = String.trim(message) |> String.split(" ", parts: 3)

    # Handle Error Reports:
    if length(split_message) == 3 and String.starts_with?(hd(split_message), "error_") do
      [error_message, specifier, data] = split_message

      Logger.error(
        "Error message received: #{error_message}, specifier: #{specifier}, data: #{data}"
      )
    else
      # Handle all Normal SECoP Messages:
      case split_message do
        ["update", specifier, data] -> update(node_id, specifier, data)
        ["describing", specifier, data] -> describe(node_id, specifier, data)
        ["inactive"] -> inactive(node_id)
        ["pong", id, data] -> pong(node_id, id, data)
        ["active"] -> active(node_id)
        ["reply", specifier, data] -> reply(node_id, specifier, data)
        ["changed", specifier, data] -> changed(node_id, specifier, data)
        ["done", specifier, data] -> done(node_id, specifier, data)
        _ -> Logger.warning("Unknown message received: #{message}")
      end
    end
  end

  defp splitSpecifier(specifier) do
    case String.split(specifier, ":", parts: 2) do
      [module, parameter] -> {:ok, module, parameter}
      _ -> {:error, :no_match}
    end
  end

  defp data_to_ets(node_id, specifier, data) do
    {:ok, data_report} = Jason.decode(data)

    {:ok, module, accessible} = splitSpecifier(specifier)

    {:ok, :inserted} = NodeTable.insert(node_id, {:data_report, module, accessible}, data_report)

    {:ok, module, accessible, data_report}
  end

  def update(node_id, specifier, data) do
    # Logger.debug("Update message received. Specifier: #{specifier}, Data: #{data}")
    data_to_ets(node_id, specifier, data)
  end

  def describe(node_id, specifier, data) do
    # Logger.debug("Describe message received. Specifier: #{specifier}, Data: #{data}")
    {:ok, description} = Jason.decode(data,[keys: :atoms])

    parsed_description = parse__node_description(description)


    {:ok, :inserted} = NodeTable.insert(node_id, :description, parsed_description)
    {:ok, :inserted} = NodeTable.insert(node_id, :raw_description, description)

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:describe, specifier, parsed_description})
      end
    end)
  end

  def inactive(node_id) do
    Logger.debug("Deactivated update messages received.")

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:inactive})
      end
    end)
  end

  def pong(node_id, id, data) do
    Logger.debug("Pong received. ID: #{id}, Data: #{data}")

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:pong, id, data})
      end
    end)
  end

  def active(node_id) do
    Logger.debug("Active message received.")

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:active})
      end
    end)
  end

  def reply(node_id, specifier, data) do
    Logger.debug("Read reply received. Specifier: #{specifier}, Data: #{data}")
    {:ok, module, parameter, data_report} = data_to_ets(node_id, specifier, data)

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:reply, module, parameter, data_report})
      end
    end)
  end

  def changed(node_id, specifier, data) do
    Logger.debug("Parameter successfully changed. Specifier: #{specifier}, Data: #{data}")
    {:ok, module, parameter, data_report} = data_to_ets(node_id, specifier, data)

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:changed, module, parameter, data_report})
      end
    end)
  end

  def done(node_id, specifier, data) do
    Logger.debug("Command executed. Specifier: #{specifier}, Data: #{data}")
    {:ok, module, command, data_report} = data_to_ets(node_id, specifier, data)

    Registry.dispatch(Registry.SEC_Node_Statem, node_id, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:done, module, command, data_report})
      end
    end)
  end

  def get_empty_values_map(description) do
    modules = description[:modules]

    empty_values_map =
      Enum.reduce(modules, %{}, fn {module_name, module_data}, acc ->
        parameters = module_data[:parameters]

        Map.put(acc, module_name, parameters)
      end)


    {:ok, empty_values_map}
  end



  def parse__node_description(description) do
    node_descripttion = %{
      properties: Map.drop(description, [:modules])
    }

    # add all run parse_module_description for each module in desctription[:modules] and put result in a map
    modules = Enum.reduce(description[:modules], %{}, fn {module_name, module_description}, acc ->
      parsed_module_description = parse_module_description(module_description)
      Map.put(acc, module_name, parsed_module_description)
    end)

    node_descripttion = Map.put(node_descripttion,:modules,modules)


    node_descripttion
  end

  def parse_module_description(module_description) do
    {parameters, commands} =
      Enum.reduce(module_description[:accessibles], {%{}, %{}}, fn {accessible_name, accessible_data}, {param_acc, cmd_acc} ->
        if accessible_data[:datainfo][:type] != "command" do
          {Map.put(param_acc, accessible_name, accessible_data), cmd_acc}
        else
          {param_acc, Map.put(cmd_acc, accessible_name, accessible_data)}
        end
      end)


    parsed_module_description = %{
      properties: Map.drop(module_description, [:accessibles]),
      parameters: parameters,
      commands: commands
    }




    parsed_module_description
  end




end
