import gavel_rules/increment
import gavel_rules/types.{
  type Command, type Config, type Decision, type Event, type Rejection,
  type State, AlreadyHighBidder, AuctionClosed, BelowMinimum, Bid, BidAccepted,
  Close, Closed, Duplicate, Emit, Extended, InvalidAmount, InvalidConfig,
  NotOpen, NotYetEnded, Open, Opened, Pending, PlaceBid, SellerCannotBid, State,
  TooLate,
}
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

pub fn minimum_next_bid(state: State) -> Int {
  case state.config, state.high_bid {
    None, _ -> 0
    Some(config), None -> config.starting_price
    Some(_), Some(high) -> high.amount + increment.increment(high.amount)
  }
}

pub fn new() -> State {
  State(None, Pending, None, [], dict.new(), 0, 0, 0)
}

pub fn evolve(state: State, event: Event) -> State {
  case event {
    Opened(c) ->
      State(
        ..state,
        config: Some(c),
        status: Open,
        ends_at: c.ends_at,
        seq: state.seq + 1,
      )
    BidAccepted(b) ->
      State(
        ..state,
        high_bid: Some(b),
        bids: [b, ..state.bids],
        accepted: dict.insert(state.accepted, b.request_id, b),
        seq: state.seq + 1,
      )
    Extended(t) ->
      State(
        ..state,
        ends_at: t,
        extensions_used: state.extensions_used + 1,
        seq: state.seq + 1,
      )
    AuctionClosed(_) -> State(..state, status: Closed, seq: state.seq + 1)
  }
}

pub fn decide(
  state: State,
  command: Command,
  now: Int,
) -> Result(Decision, Rejection) {
  use <- bool.guard(state.status == Pending, Error(NotOpen))
  case command {
    Close -> decide_close(state, now)
    PlaceBid(request_id, bidder, amount) ->
      case dict.get(state.accepted, request_id) {
        Ok(existing) -> Ok(Duplicate(existing))
        Error(_) -> decide_place_bid(state, request_id, bidder, amount, now)
      }
  }
}

fn decide_close(state: State, now: Int) -> Result(Decision, Rejection) {
  use <- bool.guard(now < state.ends_at, Error(NotYetEnded))
  Ok(Emit([AuctionClosed(state.high_bid)]))
}

fn decide_place_bid(
  state: State,
  request_id: String,
  bidder: String,
  amount: Int,
  now: Int,
) -> Result(Decision, Rejection) {
  use <- bool.guard(now >= state.ends_at, Error(TooLate))
  use <- bool.guard(is_seller(state, bidder), Error(SellerCannotBid))
  use <- bool.guard(is_high_bidder(state, bidder), Error(AlreadyHighBidder))
  use <- bool.guard(amount <= 0, Error(InvalidAmount))
  let minimum = minimum_next_bid(state)
  use <- bool.guard(amount < minimum, Error(BelowMinimum(minimum)))
  let events = [
    BidAccepted(Bid(request_id, bidder, amount, now)),
    ..maybe_extend(state, now)
  ]
  Ok(Emit(events))
}

fn maybe_extend(state: State, now: Int) -> List(Event) {
  case state.config {
    None -> []
    Some(config) -> {
      use <- bool.guard(state.extensions_used >= config.max_extensions, [])
      let in_window = state.ends_at - now <= config.snipe_window_ms
      use <- bool.guard(!in_window, [])
      let new_ends_at = now + config.extension_ms
      use <- bool.guard(new_ends_at <= state.ends_at, [])
      [Extended(new_ends_at)]
    }
  }
}

pub fn fold(events: List(Event)) -> State {
  list.fold(events, new(), evolve)
}

pub fn open(config: Config) -> Result(List(Event), Rejection) {
  use <- invalid_when(config.title == "", "title")
  use <- invalid_when(config.seller == "", "seller")
  use <- invalid_when(config.starting_price <= 0, "starting_price")
  use <- invalid_when(
    option.map(config.reserve, fn(r) { r <= 0 }) |> option.unwrap(False),
    "reserve",
  )
  use <- invalid_when(config.ends_at <= 0, "ends_at")
  use <- invalid_when(config.snipe_window_ms < 0, "snipe_window_ms")
  use <- invalid_when(config.extension_ms < 0, "extension_ms")
  use <- invalid_when(config.max_extensions < 0, "max_extensions")
  Ok([Opened(config)])
}

fn invalid_when(
  condition: Bool,
  field: String,
  next: fn() -> Result(List(Event), Rejection),
) -> Result(List(Event), Rejection) {
  bool.guard(condition, Error(InvalidConfig(field)), next)
}

fn is_seller(state: State, bidder: String) -> Bool {
  case state.config {
    Some(config) -> config.seller == bidder
    None -> False
  }
}

fn is_high_bidder(state: State, bidder: String) -> Bool {
  case state.high_bid {
    Some(high) -> high.bidder == bidder
    None -> False
  }
}
