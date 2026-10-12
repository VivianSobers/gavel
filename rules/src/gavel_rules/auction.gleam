import gavel_rules/increment
import gavel_rules/types.{
  type Command, type Config, type Decision, type Event, type Rejection,
  type State, Bid, BidAccepted, Close, Emit, InvalidConfig, NotOpen, NotYetEnded,
  Open, Opened, Pending, PlaceBid, State,
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
    _ -> State(..state, seq: state.seq + 1)
  }
}

pub fn decide(
  state: State,
  command: Command,
  now: Int,
) -> Result(Decision, Rejection) {
  use <- bool.guard(state.status == Pending, Error(NotOpen))
  case command {
    Close -> Error(NotYetEnded)
    PlaceBid(request_id, bidder, amount) ->
      Ok(Emit([BidAccepted(Bid(request_id, bidder, amount, now))]))
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
