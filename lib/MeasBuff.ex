defmodule MeasBuff do
  @moduledoc """
  A module for handling a measurement buffer using an Erlang queue.
  """

  defstruct buffer: :queue.new(), buffer_sparkline: :queue.new(), buff_len: 0


  @max_duration 30*60*60
  @max_buffer_len 2000

  @type t :: %MeasBuff{
          buffer: :queue.queue(any()),
          buffer_sparkline: :queue.queue(any()),
          buff_len: non_neg_integer()
        }

  def get_max_buffer_len() do
    @max_buffer_len
  end

  def get_max_duration() do
    @max_duration
  end


  def get_buffer_list(%MeasBuff{buffer: buffer} = _measbuff) do
    :queue.to_list(buffer)
  end

  def get_spark_list(%MeasBuff{buffer_sparkline: buffer_sparkline} = _measbuff) do
    :queue.to_list(buffer_sparkline)
  end

  @spec remove_reading(t()) :: t()
  def remove_reading(%MeasBuff{buffer: buffer, buffer_sparkline: buffer_sparkline, buff_len: buff_len} = meas_buff) do

    {stat_spark ,new_buffer_sparkline} =:queue.out(buffer_sparkline)
    {stat_buff  ,new_buffer} =:queue.out(buffer)

    case {{stat_buff  ,new_buffer},{stat_spark ,new_buffer_sparkline}} do
      {{{:value, _}, new_buffer},{{:value, _}, new_buffer_sparkline}} ->
        %MeasBuff{meas_buff | buffer: new_buffer,buffer_sparkline: new_buffer_sparkline, buff_len: max(buff_len - 1, 0)}

      {{:empty, _},{:empty,_}} ->
        meas_buff
    end
  end

  @spec enqueue(t(),float(),any()) :: t()
  def enqueue(%MeasBuff{buffer: buffer, buffer_sparkline: buffer_sparkline, buff_len: buff_len} = measbuff, timestamp, value)do
    buffer =  :queue.in({timestamp, value},buffer)
    buffer_sparkline = :queue.in(value,buffer_sparkline)

    buff_len = buff_len + 1

    %MeasBuff{measbuff | buffer: buffer, buffer_sparkline: buffer_sparkline, buff_len: buff_len}

  end


  @spec add_reading(t(), any()) :: t()
  def add_reading(measbuff,data_report) do
    [value, qualifiers] = data_report

    new_measbuff =case qualifiers do
      %{t: timestamp} -> enqueue(measbuff,timestamp,value) |> clean_up()

      _ -> measbuff

    end

    new_measbuff
  end



  @spec clean_up(t()) ::t()
  def clean_up(%MeasBuff{buffer: buffer, buff_len: buff_len} = measbuff) do

    new_measbuff = if buff_len > 0 do

        {:value,{t_front_peek, _v_peek}} = :queue.peek(buffer)
        {:value,{t_rear_peek, _v_peek}} = :queue.peek_r(buffer)

        tdiff =   t_rear_peek - t_front_peek



        measbuff = cond do

          buff_len > @max_buffer_len -> remove_reading(measbuff) |> clean_up()

          tdiff > @max_duration ->  remove_reading(measbuff) |> clean_up()

          true -> measbuff
        end
        measbuff
    else
      measbuff
    end

    new_measbuff
  end


end
