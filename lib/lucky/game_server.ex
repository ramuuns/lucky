defmodule GameServer do
    use GenServer

    def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts)
    end

    def get(pid, name) do
        GenServer.call(pid, {:get, name})
    end

    def create(pid, name) do
        GenServer.cast(pid, {:create, name})
    end

    def init(:ok) do
        {:ok, %{}}
    end

    def handle_call({:get, name}, _from, games) do
        {:reply, Map.fetch(games, name), games}
    end

    def handle_cast({:create, name}, games) do
        if Map.has_key?(games, name) do
            {:noreply, games}
        else
            {:ok, game} = GenServer.start_link(Game, :ok)
            {:noreply, Map.put(games, name, game)}
        end
    end
end
