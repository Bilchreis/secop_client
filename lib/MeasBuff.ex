defmodule MeasBuff do
  @moduledoc """
  A module for handling a measurement buffer using an Erlang queue.
  """

  defstruct buffer_value: :queue.new(), buffer_timestamp: :queue.new(), buff_len: 0

  @max_duration 30 * 60
  @max_buffer_len 2000

  @type t :: %MeasBuff{
          buffer_value: :queue.queue(any()),
          buffer_timestamp: :queue.queue(any()),
          buff_len: non_neg_integer()
        }

  def get_max_buffer_len() do
    @max_buffer_len
  end

  def get_max_duration() do
    @max_duration
  end

  def get_buffer_list(
        %MeasBuff{
          buffer_value: buffer_value,
          buffer_timestamp: buffer_timestamp
        } = _measbuff
      ) do
    val_list = :queue.to_list(buffer_value)
    ts_list = :queue.to_list(buffer_timestamp)

    {val_list, ts_list}
  end

  def get_spark_list(%MeasBuff{buffer_value: buffer_value} = _measbuff) do
    :queue.to_list(buffer_value)
  end

  @spec remove_reading(t()) :: t()
  def remove_reading(
        %MeasBuff{
          buffer_value: buffer_value,
          buffer_timestamp: buffer_timestamp,
          buff_len: buff_len
        } = meas_buff
      ) do
    {stat_val, new_buffer_value} = :queue.out(buffer_value)
    {stat_timestamp, new_buffer_timestamp} = :queue.out(buffer_timestamp)

    case {{stat_val, new_buffer_value}, {stat_timestamp, new_buffer_timestamp}} do
      {{{:value, _}, new_buffer_value}, {{:value, _}, new_buffer_timestamp}} ->
        %MeasBuff{
          meas_buff
          | buffer_value: new_buffer_value,
            buffer_timestamp: new_buffer_timestamp,
            buff_len: max(buff_len - 1, 0)
        }

      {{:empty, _}, {:empty, _}} ->
        meas_buff
    end
  end

  @spec enqueue(t(), float(), any()) :: t()
  def enqueue(
        %MeasBuff{
          buffer_value: buffer_value,
          buffer_timestamp: buffer_timestamp,
          buff_len: buff_len
        } = measbuff,
        timestamp,
        value
      ) do
    buffer_value = :queue.in(value, buffer_value)
    buffer_timestamp = :queue.in(timestamp, buffer_timestamp)

    buff_len = buff_len + 1

    %MeasBuff{
      measbuff
      | buffer_value: buffer_value,
        buffer_timestamp: buffer_timestamp,
        buff_len: buff_len
    }
  end

  @spec add_reading(t(), any()) :: t()
  def add_reading(measbuff, data_report) do
    [value, qualifiers] = data_report

    new_measbuff =
      case qualifiers do
        %{t: timestamp} -> enqueue(measbuff, timestamp, value) |> clean_up()
        _ -> measbuff
      end

    new_measbuff
  end

  @spec clean_up(t()) :: t()
  def clean_up(
        %MeasBuff{
          buffer_value: buffer_value,
          buffer_timestamp: buffer_timestamp,
          buff_len: buff_len
        } = measbuff
      ) do
    new_measbuff =
      if buff_len > 0 do
        {:value, t_front_peek} = :queue.peek(buffer_timestamp)
        {:value, t_rear_peek} = :queue.peek_r(buffer_timestamp)

        tdiff = t_rear_peek - t_front_peek

        measbuff =
          cond do
            buff_len > @max_buffer_len -> remove_reading(measbuff) |> clean_up()
            tdiff > @max_duration -> remove_reading(measbuff) |> clean_up()
            true -> measbuff
          end

        measbuff
      else
        measbuff
      end

    new_measbuff
  end
end
