defmodule Game do
    use GenServer
    
    @impl true
    def init(_) do
        {:ok, %{ dice: nil, bet: nil, state: :unstarted, players: [], did_peek: false, blind_bet: false }}
    end

    def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts)
    end

    def roll_dice(pid) do
        GenServer.call(pid, :roll_dice)
    end

    def get_state(pid) do
        GenServer.call(pid, :get_state)
    end

    def peek(pid) do
        GenServer.call(pid, :peek)
    end

    def bet(pid, bet) do
        GenServer.call(pid, {:bet, bet})
    end

    def accept(pid) do
        GenServer.call(pid, :accept)
    end

    def reject(pid) do
        GenServer.call(pid, :reject)
    end

    def add_player(pid, %{name: _ } = player) do
        GenServer.call(pid, {:add_player, player})
    end

    def remove_player(pid, %{name: _} = player) do
        GenServer.call(pid, {:remove_player, player})
    end

    def start(pid) do
        GenServer.call(pid, :start)
    end

    def handle_call(:start, _from, game) do
        num_players = length(game.players)
        {ok, game} = cond do
            game.state == :unstarted and num_players >= 2 ->
                %{ ord: min_ord } = Enum.min_by(game.players, fn pl -> pl.ord end)
                {:ok, %{ game | state: :pre_roll, players: Enum.map(game.players, fn pl ->
                    cond do
                        pl.ord == min_ord -> %{ pl | is_current: true }
                        true -> pl
                    end
                 end) } }
            true -> {:notok, game}
        end
        {:reply, {ok, game}, game}
    end

    def handle_call({:add_player, player}, _from, game) do
        exists_player? = not Enum.empty?(Enum.filter(game.players, fn pl -> pl.name == player.name end))
        {ok, game} = case exists_player? do
            true -> {:notok, game}
            false ->
                max_ord = case Enum.max_by(game.players, fn pl -> pl.ord end, &>=/2, fn -> 0 end) do
                    %{ ord: max_ord } -> max_ord
                    _ -> 0
                end
                player = Map.put(player, :ord, max_ord + 1)
                player = Map.put(player, :is_current, false)
                {:ok, %{ game | players: [ player | game.players ] } }
        end
        {:reply, {ok, game}, game}
    end

    def handle_call({:remove_player, player}, _from, game) do
        exists_player? = not Enum.empty?(Enum.filter(game.players, fn pl -> pl.name == player.name end))
        {ok, game} = case exists_player? do
            false -> {:notok, game}
            true ->
                gm_player = Enum.find(game.players, fn pl -> pl.name == player.name end)
                case gm_player do
                    %{ is_current: false} ->
                        {:ok, %{ game | players: Enum.filter(game.players, fn pl -> pl.name != player.name end) } } 
                    %{ is_current: true } ->
                        {:ok, %{ game | players: Enum.filter(set_next(game.players), fn pl -> pl.name != player.name end), bet: nil, dice: nil, state: :pre_roll, did_peek: false, blind_bet: false}}
                end
        end
        {:reply, {ok, game}, game}
    end

    @impl true
    def handle_call(:roll_dice, _from, game) do
        newstate = case game.state do
            :pre_roll -> :roll_1
            :prev_loss -> :roll_1
            :curr_loss -> :roll_1
            :accepted -> :roll_1
            :peeked -> :roll_2
            _ -> game.state
        end
        game = cond do
            game.state == newstate -> game
            true ->
                d1 = :rand.uniform(6)
                d2 = :rand.uniform(6)
                %{ game | 
                    dice: cond do
                        d1 > d2 -> { d1, d2 }
                        true -> {d2, d1 }
                    end,
                    state: newstate
                }
        end
        {:reply, game, game}
    end

    def handle_call(:get_state, _from, game) do
        {:reply, game, game}
    end

    def handle_call(:peek, _from, game) do
        {ret, game} = case game.state do
            :roll_1 -> { game.dice, %{ game | state: :peeked, did_peek: true } }
            _ -> { nil, game }
        end
        {:reply, ret, game}
    end

    def handle_call({:bet, bet}, _from, game) do
        {a, b} = bet
        a = cond do 
            a > 6 -> 6
            a < 1 -> 1
            true -> a
        end
        b = cond do
            b > 6 -> 6
            b < 1 -> 1
            true -> b
        end
        bet = cond do
            b > a -> { b, a }
            true -> { a, b }
        end
        game = case bet_is_higher(bet, game.bet) do
            false -> game
            true -> case game.state do
                :roll_1 -> %{ game | bet: bet, state: :passed, players: set_next(game.players), blind_bet: true }
                :peeked -> %{ game | bet: bet, state: :passed, players: set_next(game.players), blind_bet: false }
                :roll_2 -> %{ game | bet: bet, state: :passed, players: set_next(game.players), blind_bet: true }
                :accepted -> %{ game | bet: bet, state: :passed, players: set_next(game.players), blind_bet: true }
                _ -> game
            end
        end
        {:reply, game, game}
    end

    def handle_call(:accept, _from, game) do
        game = case game.state do
            :passed -> %{ game | state: :accepted, did_peek: false, blind_bet: false }
            _ -> game
        end
        {:reply, game, game}
    end

    def handle_call(:reject, _from, game) when game.state != :passed do
         {:reply, %{prev_bet: nil, prev_dice: nil, game: game}, game}
    end

    def handle_call(:reject, _from, game) do
        {bet, dice, loser, game} = case bet_is_higher(game.dice, game.bet) or bet_is_equal(game.bet, game.dice) do
            true -> {game.bet, game.dice, get_current(game.players), %{ game | state: :curr_loss, bet: nil, dice: nil, did_peek: false, blind_bet: false  } }
            false -> {game.bet, game.dice, get_previous(game.players), %{ game | state: :prev_loss, bet: nil, dice: nil, did_peek: false, blind_bet: false } }
        end
        {:reply, %{prev_bet: bet, prev_dice: dice, game: game, loser: loser}, game}
    end

    defp set_next(players) do
        %{ ord: curr } = Enum.find(players, fn pl -> pl.is_current end)
        candidate_next = players |> Enum.filter(fn p -> p.ord > curr end)
        first_guy = Enum.min_by(players, fn p -> p.ord end) 
        %{ ord: next_ord } = cond do
            Enum.empty?( candidate_next) -> first_guy
            true ->  Enum.min_by(candidate_next, fn p -> p.ord end)
        end
        players |> Enum.map(fn pl -> %{ pl | is_current: pl.ord == next_ord } end)    
    end

    defp get_current(players) do
        Enum.find(players, fn pl -> pl.is_current end)
    end

    defp get_previous(players) do
        %{ ord: curr } = Enum.find(players, fn pl -> pl.is_current end)
        candidate_prev =  players |> Enum.filter(fn p -> p.ord < curr end)
        cond do
            Enum.empty?( candidate_prev ) -> Enum.max_by(players, fn p -> p.ord end)
            true -> Enum.max_by(candidate_prev, fn p -> p.ord end)
        end
    end

    def bet_is_equal({a, b}, {a, b}) do
        true
    end
    
    def bet_is_equal(_, _) do
        false
    end

    def bet_is_higher(_, nil) do
        true
    end

    def bet_is_higher(_, {2, 1}) do
        false
    end
    
    def bet_is_higher({2,1}, _) do
        true
    end

    def bet_is_higher({n, n}, {p, p}) do
        n > p
    end

    def bet_is_higher({n,n}, _ )  do
        true
    end

    def bet_is_higher(_, { p, p }) do
        false
    end

    def bet_is_higher({h, nl}, {h, ol}) do
        nl > ol
    end

    def bet_is_higher({h, _}, {l, _}) do
        h > l
    end
end
