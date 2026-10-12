import gavel_rules/types.{
  type Config, type Event, type Rejection, type State, InvalidConfig, Opened,
  Pending, State,
}
import gleam/bool
import gleam/dict
import gleam/option.{None}

pub fn new() -> State {
  State(None, Pending, None, [], dict.new(), 0, 0, 0)
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
