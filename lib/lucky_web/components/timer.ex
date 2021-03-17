defmodule Timer do
  use Surface.LiveComponent

  data time, :number, default: nil

  def mount(socket) do
    socket = Surface.init(socket)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <span class="timer" :if={{ @time != nil }}>{{ @time }}</span>
    """
  end

  def setTime(timer_id, time) do
    send_update(__MODULE__, id: timer_id, time: time)
  end
end
