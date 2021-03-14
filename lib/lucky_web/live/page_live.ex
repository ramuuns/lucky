defmodule LuckyWeb.PageLive do
  use LuckyWeb, :live_view

  def render(assigns) do
    ~H"""
        <h1>Hello world</h1>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

end
