defmodule LuckyWeb.GameLive do
  use LuckyWeb, :live_view
  alias Lucky.Presence

  def render_bet(bet) do
    {bet0, bet1 } = bet
    "#{ bet0 }, #{ bet1 }"
  end

  @impl true
  def render(assigns) do
    ~H"""
        <h1>Spēle {{ @name }}</h1>
        <form :on-submit="join" :if={{ @username == nil }}>
            <label>Kā tevi dēvēt? <input type="text" name="username" /></label>
            <button type="submit">Ienākt</button>
        </form>
        <div :if={{ @username != nil }}>
            <h2>čau {{ @username }}</h2>
            <ul>
                <li :for={{ player <- @game_state.players }}>
                   <span :if={{ player.is_current }}>&gt;</span> {{ player.name }}
                </li>
            </ul>
            <button :on-click="start" :if={{ can_start(@username, @game_state) }}>Sākt</button>
            <div :if={{ @previous_round != nil }}>
                <h3>Iepriekšējais raunds:</h3>
                <p>Zaudēja {{ @previous_round.loser.name }}</p>
                <p>Likme: {{ render_bet(@previous_round.prev_bet) }}</p>
                <p>Kauli: {{ render_bet(@previous_round.prev_dice) }}</p>
            </div>
            <div :if={{ @game_state.bet != nil }}>
                Likme: {{ render_bet(@game_state.bet) }}
            </div>
            <div :if={{ @game_state.state != :unstarted and is_current(@username, @game_state.players) }}>
                <button :on-click="roll" :if={{ can_roll(@game_state) }}>Kratīt</button>
                <button :on-click="peek" :if={{ can_peek(@game_state) }}>Pastītites</button>
                <div :if={{ is_peeking(@game_state) }}>
                    Uzmests: {{ render_bet( @game_state.dice) }}
                </div>
                <form :on-submit="bet" :if={{ can_bet(@game_state) }}>
                <label>likme <select name="bet">
                    <option :for={{ option <- bet_options(@game_state) }} value={{ render_bet(option) }}>{{ render_bet(option) }}</option>
                </select></label>
                <button type="submit">Aiziet</button>
                </form>
                <div :if={{ is_passed(@game_state) }}>
                    <span :if={{ @game_state.did_peek }}>Skatījās</span>
                    <span :if={{ @game_state.blind_bet }}>Dod uz aklo</span>
                    <button :on-click="accept" :if={{ can_accept(@game_state) }}>Ticu</button>
                    <button :on-click="reject">Meli!!!</button>
                </div>
            </div>
        </div>
    """
  end

  defp bet_options(%{ bet: bet }) do
    options = [ 
        {3, 1}, {3, 2},
        {4, 1}, {4, 2}, {4, 3},
        {5, 1}, {5, 2}, {5, 3}, {5, 4},
        {6, 1}, {6, 2}, {6, 3}, {6, 4}, {6, 5},
        {1, 1}, {2, 2}, {3, 3}, {4, 4}, {5, 5}, {6, 6},
        {2, 1} ]
    Enum.filter(options, fn opt -> Game.bet_is_higher(opt, bet) end)
  end

  defp can_accept(%{ bet: {2, 1}}) do
    false
  end

  defp can_accept(_) do
    true
  end

  defp is_current(username, players) do
    me = Enum.find(players, fn pl -> pl.name == username end)
    me.is_current
  end

  defp can_start(username, state) do
    player_who_can = Enum.min_by(state.players, fn pl -> pl.ord end)
    state.state == :unstarted and player_who_can.name == username
  end

  defp can_roll(%{ state: state }) do
    case state do
        :pre_roll -> true
        :prev_loss -> true
        :curr_loss -> true
        :accepted -> true
        :peeked -> true
        _ -> false
    end
  end

  defp is_passed(%{ state: :passed }) do
    true
  end

  defp is_passed(_) do
    false
  end

  defp can_bet(%{ dice: nil }) do
    false
  end

  defp can_bet(%{ state: :passed }) do
    false
  end

  defp can_bet(_) do
    true
  end

  defp can_peek(%{ state: :roll_1 }) do
    true
  end

  defp can_peek(_) do
    false
  end

  defp is_peeking(%{ state: :peeked }) do
    true
  end

  defp is_peeking(_) do
    false 
  end

  @impl true
  def mount(params, _session, socket) do
    GameServer.create(Lucky.GameServer, params["name"])
    {:ok, game} = GameServer.get(Lucky.GameServer, params["name"])
    socket = socket 
        |> assign(:name, params["name"])
        |> assign(:game, game)
        |> assign(:game_state, Game.get_state(game))
        |> assign(:username, nil)
        |> assign(:previous_round, nil)
    {:ok, socket}
  end

  @impl true
  def handle_event("join", %{ "username" => username }, socket) do
    username = String.trim(username)
    socket = case username do
       "" -> socket |> put_flash(:error, "Ieraksti vārdu varbūt :)")
       _ ->
        game = socket.assigns.game
        %{ players: players } = Game.get_state(game)
        ok? = Enum.empty?(Enum.filter(players, fn pl -> pl.name == username end))
        case ok? do
            false -> socket |> put_flash(:error, "Šāds spēlētājs jau ir spēlē, sauc sevi citādāk")
            true -> 
                {_, game_state} = Game.add_player(game, %{ name: username })
                Presence.track_presence(
                  self(),
                  socket.assigns.name,
                  username,
                  %{ name: username }
                )
                LuckyWeb.Endpoint.subscribe(socket.assigns.name)
                socket |> assign(:username, username) |> assign(:game_state, game_state)
        end 
    end
    {:noreply, socket}
  end

  @impl true 
  def handle_event("start", _, socket) do
    game = socket.assigns.game
    Game.start(game)
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "update", :ok)
    {:noreply, socket |> assign(:game_state, Game.get_state(game))}
  end

  @impl true
  def handle_event("roll", _, socket) do
    game = socket.assigns.game
    Game.roll_dice(game)
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "update", :ok)
    {:noreply, socket |> assign(:game_state, Game.get_state(game))}
  end

  @impl true
  def handle_event("peek", _, socket) do
    game = socket.assigns.game
    Game.peek(game)
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "update", :ok)
    {:noreply, socket |> assign(:game_state, Game.get_state(game))}
  end

  @impl true
  def handle_event("bet", %{ "bet" => bet }, socket) do
    game = socket.assigns.game
    [bet0, bet1] = Enum.map(String.split(bet, ", "), fn st -> String.to_integer(st) end)
    Game.bet(game, {bet0, bet1})
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "update", :ok)
    {:noreply, socket |> assign(:game_state, Game.get_state(game))}
  end

  @impl true
  def handle_event("accept", _, socket) do
    game = socket.assigns.game
    Game.accept(game)
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "update", :ok)
    {:noreply, socket |> assign(:game_state, Game.get_state(game))}
  end

  @impl true
  def handle_event("reject", _, socket) do
    game = socket.assigns.game
    %{  loser: loser,
        prev_bet: prev_bet,
        prev_dice: prev_dice } = Game.reject(game)
    LuckyWeb.Endpoint.broadcast_from(self(), socket.assigns.name, "game_end", %{ loser: loser, prev_bet: prev_bet, prev_dice: prev_dice })
    {:noreply, socket |> assign(:game_state, Game.get_state(game)) |> assign(:previous_round, %{ loser: loser, prev_bet: prev_bet, prev_dice: prev_dice }) }
  end

  @impl true
  def handle_info(%{event: "presence_diff"} = full_event, socket) do
    game = socket.assigns.game
    socket = case full_event.payload do
        %{ leaves: leavers } ->
            for name <- Map.keys(leavers) do
                Game.remove_player(game, %{ name: name })
            end
            socket |> assign(:game_state, Game.get_state(game))
        _ -> 
            socket |> assign(:game_state, Game.get_state(game))
    end
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "update"}, socket ) do
    game = socket.assigns.game
    {:noreply, socket |> assign(:game_state, Game.get_state(game)) }
  end

  def handle_info(%{event: "game_end", payload: prev_round}, socket) do
    game = socket.assigns.game
    {:noreply, socket |> assign(:game_state, Game.get_state(game)) |> assign(:previous_round, prev_round) }
  end

end
