defmodule GavelWeb.AuctionLiveTest do
  use GavelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gavel.Clock
  alias Gavel.Router
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store

  @now 1_699_000_000_000
  @ends_at @now + 3_600_000

  defmodule UnavailableRpc do
    @moduledoc false

    alias Gavel.Cluster.Rpc
    alias GavelWeb.AuctionLiveTest

    def call(_node, _module, _function, [_id, {:place_bid, request_id, _, _}], _timeout) do
      send(AuctionLiveTest, {:attempt, request_id})
      {:error, :unavailable}
    end

    def call(node, module, function, args, timeout) do
      Rpc.call(node, module, function, args, timeout)
    end
  end

  defmodule DownRpc do
    @moduledoc false

    def call(_node, _module, _function, _args, _timeout), do: {:error, :unavailable}
  end

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    Clock.Test.set(@now)
    :ok
  end

  defp create_auction(attrs \\ []) do
    config =
      struct!(
        %Config{
          title: "Rare Coin",
          seller: "alice",
          starting_price: 1_000,
          reserve: nil,
          ends_at: @ends_at,
          snipe_window_ms: 1_000,
          extension_ms: 1_000,
          max_extensions: 5
        },
        attrs
      )

    {:ok, id} = Store.create_auction(config)
    id
  end

  defp bid(id, request_id, bidder, amount) do
    assert {:accepted, _bid, _view} =
             Router.dispatch(id, {:place_bid, request_id, bidder, amount})
  end

  defp close(id) do
    Clock.Test.set(@ends_at)

    # A server started by this command closes the overdue auction while loading.
    reply = Router.dispatch(id, :close)
    assert match?({:closed, _winner, _view}, reply) or reply == {:rejected, :already_closed}
  end

  defp submit_bid(view, bidder, amount) do
    view |> form("#bid-form", bid: %{bidder: bidder, amount: amount}) |> render_submit()
  end

  describe "creating an auction" do
    @valid %{
      title: "Old Map",
      seller: "alice",
      starting_price: "10.00",
      reserve: "",
      duration_minutes: "60"
    }

    test "refuses a duration over a year", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      html =
        view
        |> form("#auction-form", auction: %{@valid | duration_minutes: "9999999999"})
        |> render_submit()

      assert html =~ "up to one year"
      assert Store.open_auction_ids() == []
    end

    test "opens it and goes to its page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      view |> form("#auction-form", auction: @valid) |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert [id] = Store.open_auction_ids()
      assert path == ~p"/auctions/#{id}"

      assert {:view, created} = Router.dispatch(id, :view)
      assert created.title == "Old Map"
      assert created.minimum_next_bid == 1_000
      assert created.ends_at == @now + 3_600_000
    end

    test "stores an optional reserve in cents", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      view |> form("#auction-form", auction: %{@valid | reserve: "50"}) |> render_submit()

      assert_redirect(view)
      assert [id] = Store.open_auction_ids()
      assert {:ok, [opened]} = Store.load(id)
      assert opened.config.reserve == 5_000
    end

    test "explains an amount it cannot read", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      html =
        view
        |> form("#auction-form", auction: %{@valid | starting_price: "abc"})
        |> render_submit()

      assert html =~ "Starting price must be a dollar amount"
      assert Store.open_auction_ids() == []
    end

    test "explains a config the rules reject", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      html = view |> form("#auction-form", auction: %{@valid | title: ""}) |> render_submit()

      assert html =~ "Check the title"
      assert Store.open_auction_ids() == []
    end

    test "explains a duration it cannot read", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auctions/new")

      html =
        view
        |> form("#auction-form", auction: %{@valid | duration_minutes: "0"})
        |> render_submit()

      assert html =~ "Duration must be a whole number of minutes"
      assert Store.open_auction_ids() == []
    end
  end

  describe "auction page" do
    test "shows the auction and its minimum bid", %{conn: conn} do
      id = create_auction()

      {:ok, _view, html} = live(conn, ~p"/auctions/#{id}")

      assert html =~ "Rare Coin"
      assert html =~ "alice"
      assert html =~ "$10.00"
      assert html =~ "1h 00m 00s"
    end

    test "redirects home for an unknown auction", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/auctions/#{Ecto.UUID.generate()}")
    end

    test "redirects home for an id that is not a uuid", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/auctions/nope")
    end

    test "treats an uppercase id as the same auction", %{conn: conn} do
      id = create_auction()
      upper = String.upcase(id)

      {:ok, view, _html} = live(conn, ~p"/auctions/#{upper}")

      assert Registry.lookup(Gavel.Auction.Registry, upper) == []
      bid(id, "r1", "carol", 3_300)
      assert has_element?(view, "#bid-ladder", "carol")
    end

    test "says it is closing once the time has run out", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      Clock.Test.set(@ends_at)
      send(view.pid, :tick)

      html = render(view)
      assert html =~ "Closing"
      refute html =~ "Ends in"
    end

    test "catches up on a close it never heard about", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")
      [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, id)

      # Committed behind the server's back and never broadcast, as when a node
      # dies between the commit and the broadcast.
      assert {:ok, 2} = Store.append(id, 1, [%Event{type: :closed, winner: nil}])
      ref = Process.monitor(pid)
      :ok = DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      Clock.Test.set(@ends_at)
      send(view.pid, :tick)

      assert render(view) =~ "No bids"
      refute has_element?(view, "#bid-form")
    end

    test "places a bid and shows it on the ladder", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      html = submit_bid(view, "bob", "12.50")

      assert html =~ "Bid placed"
      assert has_element?(view, "#bid-ladder", "bob")
      assert has_element?(view, "#bid-ladder", "$12.50")

      assert {:ok, [_opened, placed]} = Store.load(id)
      assert placed.bid.amount == 1_250
      assert placed.bid.bidder == "bob"
    end

    test "lists the newest bid first", %{conn: conn} do
      id = create_auction()
      bid(id, "r1", "bob", 1_000)
      bid(id, "r2", "carol", 5_000)

      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      ladder = view |> element("#bid-ladder") |> render()
      assert :binary.match(ladder, "carol") < :binary.match(ladder, "bob")
    end

    test "uses a new request id for each bid", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "bob", "10.00") =~ "Bid placed"
      assert submit_bid(view, "carol", "50.00") =~ "Bid placed"

      assert {:ok, [_opened, first, second]} = Store.load(id)
      assert first.bid.request_id != second.bid.request_id
    end

    test "explains a bid below the minimum", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "bob", "1.00") =~ "must be at least $10.00"
      assert {:ok, [_opened]} = Store.load(id)
    end

    test "explains why the seller cannot bid", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "alice", "20.00") =~ "cannot bid on your own auction"
    end

    test "explains why the high bidder cannot bid again", %{conn: conn} do
      id = create_auction()
      bid(id, "r1", "bob", 1_000)
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "bob", "20.00") =~ "already the high bidder"
    end

    test "explains an amount it cannot read without sending a bid", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "bob", "lots") =~ "Enter a dollar amount"
      assert {:ok, [_opened]} = Store.load(id)
    end

    test "requires a bidder name", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      assert submit_bid(view, "  ", "20.00") =~ "Enter your name"
      assert {:ok, [_opened]} = Store.load(id)
    end

    test "keeps the same request id until the outcome is known", %{conn: conn} do
      Process.register(self(), __MODULE__)
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      Application.put_env(:gavel, :rpc, UnavailableRpc)
      on_exit(fn -> Application.delete_env(:gavel, :rpc) end)

      assert submit_bid(view, "bob", "20.00") =~ "safe to try again"
      assert submit_bid(view, "bob", "20.00") =~ "safe to try again"

      assert_received {:attempt, first}
      assert_received {:attempt, second}
      assert first == second
    end

    test "shows another bidder's bid as it happens", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      bid(id, "r1", "carol", 3_300)

      assert has_element?(view, "#bid-ladder", "carol")
      assert render(view) =~ "$33.00"
    end

    test "ignores an update older than what it already shows", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")
      {:view, old_view} = Router.dispatch(id, :view)

      bid(id, "r1", "carol", 3_300)
      assert has_element?(view, "#bid-ladder", "carol")

      send(view.pid, {:auction_event, id, :stale_event, old_view})

      assert has_element?(view, "#bid-ladder", "carol")
    end

    test "counts down", %{conn: conn} do
      id = create_auction()
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")

      Clock.Test.advance(60_000)
      send(view.pid, :tick)

      assert render(view) =~ "59m 00s"
    end

    test "announces the winner and removes the form when it closes", %{conn: conn} do
      id = create_auction()
      bid(id, "r1", "bob", 2_000)
      {:ok, view, _html} = live(conn, ~p"/auctions/#{id}")
      assert has_element?(view, "#bid-form")

      close(id)

      assert render(view) =~ "Won by bob"
      refute has_element?(view, "#bid-form")
    end

    test "says when the reserve was not met", %{conn: conn} do
      id = create_auction(reserve: 9_000)
      bid(id, "r1", "bob", 2_000)
      close(id)

      {:ok, _view, html} = live(conn, ~p"/auctions/#{id}")

      assert html =~ "Reserve not met"
      refute html =~ "Won by"
    end

    test "says when nobody bid", %{conn: conn} do
      id = create_auction()
      close(id)

      {:ok, _view, html} = live(conn, ~p"/auctions/#{id}")

      assert html =~ "No bids"
    end
  end
end
