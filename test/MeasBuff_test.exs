defmodule MeasBuffTest  do
  use ExUnit.Case
  alias MeasBuff


  test "enqueue adds a new reading" do
    meas_buff = %MeasBuff{}
    updated_buff = MeasBuff.enqueue(meas_buff, 1.0, 42)

    assert updated_buff.buff_len == 1
    assert :queue.len(updated_buff.buffer) == 1
    assert :queue.len(updated_buff.buffer_sparkline) == 1
  end

  test "remove_reading removes an element from the buffer" do
    meas_buff = %MeasBuff{}
    meas_buff = MeasBuff.enqueue(meas_buff, 1.0, 42)
    meas_buff = MeasBuff.enqueue(meas_buff, 2.0, 43)

    updated_buff = MeasBuff.remove_reading(meas_buff)

    assert updated_buff.buff_len == 1
    assert :queue.len(updated_buff.buffer) == 1
    assert :queue.len(updated_buff.buffer_sparkline) == 1
  end

  test "removing from an empty buffer does not change state" do
    meas_buff = %MeasBuff{}
    updated_buff = MeasBuff.remove_reading(meas_buff)

    assert updated_buff == meas_buff
  end

  test "add_reading adds data with a timestamp" do
    meas_buff = %MeasBuff{}
    data_report = [99, %{t: 1.0}]

    updated_buff = MeasBuff.add_reading(meas_buff, data_report)

    assert updated_buff.buff_len == 1
    assert :queue.len(updated_buff.buffer) == 1
    assert :queue.len(updated_buff.buffer_sparkline) == 1
  end

  test "add_reading does nothing if no timestamp is present" do
    meas_buff = %MeasBuff{}
    data_report = [99, %{other_key: "missing timestamp"}]

    updated_buff = MeasBuff.add_reading(meas_buff, data_report)

    assert updated_buff.buff_len == 0
    assert :queue.len(updated_buff.buffer) == 0
    assert :queue.len(updated_buff.buffer_sparkline) == 0
  end

  test "cleanup removes old readings based on time difference" do
    meas_buff = %MeasBuff{}
    meas_buff = MeasBuff.enqueue(meas_buff, 1.0, 10)
    meas_buff = MeasBuff.enqueue(meas_buff, 2.0, 20)
    meas_buff = MeasBuff.enqueue(meas_buff, MeasBuff.get_max_duration + 10, 30)

    cleaned_buff = MeasBuff.clean_up(meas_buff)

    assert cleaned_buff.buff_len < 3  # Older readings should be removed
  end


end
