import gavel_rules/auction
import gavel_rules/types.{
  type Bid, type Config, type Event, type Rejection, type State, AuctionClosed,
  BidAccepted, Close, Emit, Extended, Opened, PlaceBid,
}
import gleam/bool
import gleam/option.{type Option}
import gleam/result

pub type HistoryError {
  MissingOpened
  Rejected(seq: Int, rejection: Rejection)
  Unexpected(seq: Int)
}

pub fn validate(events: List(Event)) -> Result(State, HistoryError) {
  case events {
    [Opened(config), ..rest] -> validate_opened(config, rest)
    _ -> Error(MissingOpened)
  }
}

fn validate_opened(
  config: Config,
  rest: List(Event),
) -> Result(State, HistoryError) {
  use _ <- result.try(
    auction.open(config)
    |> result.map_error(fn(rejection) { Rejected(1, rejection) }),
  )
  let state = auction.evolve(auction.new(), Opened(config))
  validate_rest(rest, state)
}

fn validate_rest(
  events: List(Event),
  state: State,
) -> Result(State, HistoryError) {
  case events {
    [] -> Ok(state)
    [BidAccepted(bid), ..rest] -> validate_bid(bid, rest, state)
    [AuctionClosed(winner), ..rest] -> validate_close(winner, rest, state)
    [_, ..] -> Error(Unexpected(state.seq + 1))
  }
}

fn validate_bid(
  bid: Bid,
  rest: List(Event),
  state: State,
) -> Result(State, HistoryError) {
  let seq = state.seq + 1
  use decision <- result.try(
    auction.decide(
      state,
      PlaceBid(bid.request_id, bid.bidder, bid.amount),
      bid.at,
    )
    |> result.map_error(fn(rejection) { Rejected(seq, rejection) }),
  )
  case decision {
    Emit([BidAccepted(accepted_bid)]) -> {
      use <- bool.guard(accepted_bid != bid, Error(Unexpected(seq)))
      let next_state = auction.evolve(state, BidAccepted(bid))
      validate_rest(rest, next_state)
    }
    Emit([BidAccepted(accepted_bid), Extended(expected_ends_at)]) -> {
      use <- bool.guard(accepted_bid != bid, Error(Unexpected(seq)))
      let next_state = auction.evolve(state, BidAccepted(bid))
      validate_extension(rest, next_state, expected_ends_at)
    }
    _ -> Error(Unexpected(seq))
  }
}

fn validate_extension(
  rest: List(Event),
  state: State,
  expected_ends_at: Int,
) -> Result(State, HistoryError) {
  case rest {
    [Extended(actual_ends_at), ..rest2] -> {
      let ext_seq = state.seq + 1
      use <- bool.guard(
        actual_ends_at != expected_ends_at,
        Error(Unexpected(ext_seq)),
      )
      let next_state = auction.evolve(state, Extended(actual_ends_at))
      validate_rest(rest2, next_state)
    }
    _ -> Error(Unexpected(state.seq + 1))
  }
}

fn validate_close(
  winner: Option(Bid),
  rest: List(Event),
  state: State,
) -> Result(State, HistoryError) {
  let seq = state.seq + 1
  use decision <- result.try(
    auction.decide(state, Close, state.ends_at)
    |> result.map_error(fn(rejection) { Rejected(seq, rejection) }),
  )
  case decision {
    Emit([AuctionClosed(expected_winner)]) -> {
      use <- bool.guard(winner != expected_winner, Error(Unexpected(seq)))
      let final_state = auction.evolve(state, AuctionClosed(winner))
      case rest {
        [] -> Ok(final_state)
        _ -> Error(Unexpected(final_state.seq + 1))
      }
    }
    _ -> Error(Unexpected(seq))
  }
}
