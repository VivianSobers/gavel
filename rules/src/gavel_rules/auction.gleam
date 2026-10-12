import gavel_rules/types.{
  type Config, type Event, type Rejection, type State, InvalidConfig, Open,
  Opened, Pending, State,
}
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

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
    _ -> State(..state, seq: state.seq + 1)
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
