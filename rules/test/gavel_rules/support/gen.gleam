import gavel_rules/auction
import gavel_rules/increment
import gavel_rules/types.{
  type Command, type Config, type Decision, type Rejection, type State, Close,
  Config, Emit, Opened, PlaceBid,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import qcheck

pub type AmountOffset {
  BelowByOne
  BelowByIncrement
  Zero
  Negative
  AtMinimum
  AboveByOne
  AboveByIncrement
  AboveByTwoIncrements
}

pub type Step {
  BidStep(bidder: Int, offset: AmountOffset, repeat: Bool, delta_ms: Int)
  CloseStep(delta_ms: Int)
}

fn config_generator() -> qcheck.Generator(Config) {
  use starting_price <- qcheck.bind(qcheck.bounded_int(100, 5000))
  use has_reserve <- qcheck.bind(qcheck.bool())
  use reserve_amount <- qcheck.bind(qcheck.bounded_int(
    starting_price,
    starting_price * 3,
  ))
  let reserve = case has_reserve {
    True -> Some(reserve_amount)
    False -> None
  }
  use ends_at <- qcheck.bind(qcheck.bounded_int(10_000, 60_000))
  use snipe_window_ms <- qcheck.bind(qcheck.bounded_int(1000, 5000))
  use extension_ms <- qcheck.bind(qcheck.bounded_int(1000, 5000))
  use max_extensions <- qcheck.bind(qcheck.bounded_int(0, 3))
  qcheck.return(Config(
    title: "Test Auction",
    seller: "seller",
    starting_price: starting_price,
    reserve: reserve,
    ends_at: ends_at,
    snipe_window_ms: snipe_window_ms,
    extension_ms: extension_ms,
    max_extensions: max_extensions,
  ))
}

fn amount_offset_generator() -> qcheck.Generator(AmountOffset) {
  qcheck.from_generators(qcheck.return(AtMinimum), [
    qcheck.return(BelowByOne),
    qcheck.return(BelowByIncrement),
    qcheck.return(Zero),
    qcheck.return(Negative),
    qcheck.return(AboveByOne),
    qcheck.return(AboveByIncrement),
    qcheck.return(AboveByTwoIncrements),
  ])
}

fn step_generator(max_delta: Int) -> qcheck.Generator(Step) {
  let close_gen = {
    use delta <- qcheck.map(qcheck.bounded_int(0, max_delta))
    CloseStep(delta)
  }
  let bid_gen = {
    use bidder <- qcheck.bind(qcheck.bounded_int(0, 3))
    use offset <- qcheck.bind(amount_offset_generator())
    use repeat <- qcheck.bind(
      qcheck.from_generators(qcheck.return(False), [
        qcheck.return(False),
        qcheck.return(False),
        qcheck.return(True),
      ]),
    )
    use delta <- qcheck.map(qcheck.bounded_int(0, max_delta))
    BidStep(bidder: bidder, offset: offset, repeat: repeat, delta_ms: delta)
  }
  qcheck.from_generators(bid_gen, [
    bid_gen,
    bid_gen,
    bid_gen,
    bid_gen,
    close_gen,
  ])
}

pub fn scenario() -> qcheck.Generator(#(Config, List(Step))) {
  use config <- qcheck.bind(config_generator())
  let max_delta = config.ends_at / 10
  use count <- qcheck.bind(qcheck.bounded_int(0, 40))
  use steps <- qcheck.map(qcheck.fixed_length_list_from(
    step_generator(max_delta),
    count,
  ))
  #(config, steps)
}

fn resolve_bidder(config: Config, bidder_idx: Int) -> String {
  case bidder_idx {
    0 -> config.seller
    1 -> "bidder_1"
    2 -> "bidder_2"
    _ -> "bidder_3"
  }
}

fn resolve_amount(state: State, offset: AmountOffset) -> Int {
  let min_bid = auction.minimum_next_bid(state)
  let inc = increment.increment(min_bid)
  case offset {
    BelowByOne -> min_bid - 1
    BelowByIncrement -> min_bid - inc
    Zero -> 0
    Negative -> -1
    AtMinimum -> min_bid
    AboveByOne -> min_bid + 1
    AboveByIncrement -> min_bid + inc
    AboveByTwoIncrements -> min_bid + inc * 2
  }
}

fn resolve_request_id(
  repeat: Bool,
  last_req: Option(String),
  req_counter: Int,
) -> #(String, Int, Option(String)) {
  case repeat, last_req {
    True, Some(id) -> #(id, req_counter, last_req)
    _, _ -> {
      let id = "req-" <> int.to_string(req_counter)
      #(id, req_counter + 1, Some(id))
    }
  }
}

fn apply_outcome(state: State, outcome: Result(Decision, Rejection)) -> State {
  case outcome {
    Ok(Emit(events)) -> list.fold(events, state, auction.evolve)
    _ -> state
  }
}

pub fn run(
  config: Config,
  steps: List(Step),
) -> List(#(State, Command, Int, Result(Decision, Rejection), State)) {
  let initial_state = auction.evolve(auction.new(), Opened(config))
  do_run(config, initial_state, 0, 1, None, steps, [])
}

fn do_run(
  config: Config,
  state: State,
  now: Int,
  req_counter: Int,
  last_req: Option(String),
  steps: List(Step),
  acc: List(#(State, Command, Int, Result(Decision, Rejection), State)),
) -> List(#(State, Command, Int, Result(Decision, Rejection), State)) {
  case steps {
    [] -> list.reverse(acc)
    [CloseStep(delta_ms), ..rest] -> {
      let next_now = now + delta_ms
      let command = Close
      let outcome = auction.decide(state, command, next_now)
      let next_state = apply_outcome(state, outcome)
      let record = #(state, command, next_now, outcome, next_state)
      do_run(config, next_state, next_now, req_counter, last_req, rest, [
        record,
        ..acc
      ])
    }
    [BidStep(bidder_idx, offset, repeat, delta_ms), ..rest] -> {
      let next_now = now + delta_ms
      let bidder = resolve_bidder(config, bidder_idx)
      let #(req_id, next_counter, next_last_req) =
        resolve_request_id(repeat, last_req, req_counter)
      let amount = resolve_amount(state, offset)
      let command = PlaceBid(req_id, bidder, amount)
      let outcome = auction.decide(state, command, next_now)
      let next_state = apply_outcome(state, outcome)
      let record = #(state, command, next_now, outcome, next_state)
      do_run(config, next_state, next_now, next_counter, next_last_req, rest, [
        record,
        ..acc
      ])
    }
  }
}
