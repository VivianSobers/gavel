import gavel_rules/auction
import gavel_rules/history.{MissingOpened, Rejected, Unexpected}
import gavel_rules/support/gen
import gavel_rules/types.{
  type Config, AuctionClosed, BelowMinimum, Bid, BidAccepted, Config, Emit,
  Extended, InvalidConfig, Opened,
}
import gleam/list
import gleam/option.{None, Some}
import qcheck

fn sample_config() -> Config {
  Config(
    title: "Test Auction",
    seller: "seller",
    starting_price: 1000,
    reserve: Some(5000),
    ends_at: 60_000,
    snipe_window_ms: 10_000,
    extension_ms: 10_000,
    max_extensions: 2,
  )
}

pub fn valid_generated_history_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let scenario_history = gen.run(config, steps)
  let emitted_events =
    list.flat_map(scenario_history, fn(step) {
      let #(_before, _command, _now, outcome, _after) = step
      case outcome {
        Ok(Emit(events)) -> events
        _ -> []
      }
    })
  let all_events = [Opened(config), ..emitted_events]
  let final_state = case list.last(scenario_history) {
    Ok(#(_before, _command, _now, _outcome, after)) -> after
    Error(_) -> auction.evolve(auction.new(), Opened(config))
  }
  assert history.validate(all_events) == Ok(final_state)
}

pub fn missing_opened_empty_test() {
  assert history.validate([]) == Error(MissingOpened)
}

pub fn missing_opened_first_event_not_opened_test() {
  let bid = Bid("req-1", "bidder_1", 1000, 1000)
  assert history.validate([BidAccepted(bid)]) == Error(MissingOpened)
}

pub fn invalid_opened_config_rejected_test() {
  let config = Config(..sample_config(), starting_price: 0)
  assert history.validate([Opened(config)])
    == Error(Rejected(seq: 1, rejection: InvalidConfig("starting_price")))
}

pub fn tampered_amount_fails_with_seq_test() {
  let config = sample_config()
  let bid = Bid("req-1", "bidder_1", 500, 1000)
  assert history.validate([Opened(config), BidAccepted(bid)])
    == Error(Rejected(seq: 2, rejection: BelowMinimum(1000)))
}

pub fn tampered_amount_second_bid_fails_with_seq_test() {
  let config = sample_config()
  let bid1 = Bid("req-1", "bidder_1", 1000, 1000)
  let bid2 = Bid("req-2", "bidder_2", 1050, 2000)
  assert history.validate([Opened(config), BidAccepted(bid1), BidAccepted(bid2)])
    == Error(Rejected(seq: 3, rejection: BelowMinimum(1100)))
}

pub fn removed_extended_fails_with_seq_test() {
  let config =
    Config(
      ..sample_config(),
      ends_at: 60_000,
      snipe_window_ms: 10_000,
      extension_ms: 10_000,
      max_extensions: 1,
    )
  let bid = Bid("req-1", "bidder_1", 1000, 55_000)
  let events = [Opened(config), BidAccepted(bid)]
  assert history.validate(events) == Error(Unexpected(seq: 3))
}

pub fn removed_extended_before_close_fails_with_seq_test() {
  let config =
    Config(
      ..sample_config(),
      ends_at: 60_000,
      snipe_window_ms: 10_000,
      extension_ms: 10_000,
      max_extensions: 1,
    )
  let bid = Bid("req-1", "bidder_1", 1000, 55_000)
  let events = [Opened(config), BidAccepted(bid), AuctionClosed(None)]
  assert history.validate(events) == Error(Unexpected(seq: 3))
}

pub fn wrong_winner_no_bids_fails_with_seq_test() {
  let config = sample_config()
  let fake_bid = Bid("req-fake", "fake", 1000, 100)
  let events = [Opened(config), AuctionClosed(Some(fake_bid))]
  assert history.validate(events) == Error(Unexpected(seq: 2))
}

pub fn wrong_winner_with_bids_fails_with_seq_test() {
  let config = Config(..sample_config(), reserve: None)
  let bid = Bid("req-1", "bidder_1", 1000, 1000)
  let events = [Opened(config), BidAccepted(bid), AuctionClosed(None)]
  assert history.validate(events) == Error(Unexpected(seq: 3))
}

pub fn event_after_close_fails_with_seq_test() {
  let config = sample_config()
  let bid1 = Bid("req-1", "bidder_1", 1000, 1000)
  let bid2 = Bid("req-2", "bidder_2", 1100, 2000)
  let events = [
    Opened(config),
    BidAccepted(bid1),
    AuctionClosed(None),
    BidAccepted(bid2),
  ]
  assert history.validate(events) == Error(Unexpected(seq: 4))
}

pub fn event_after_close_without_bids_fails_with_seq_test() {
  let config = sample_config()
  let events = [Opened(config), AuctionClosed(None), Extended(70_000)]
  assert history.validate(events) == Error(Unexpected(seq: 3))
}

pub fn valid_closed_history_passes_test() {
  let config = Config(..sample_config(), reserve: None)
  let bid = Bid("req-1", "bidder_1", 1000, 1000)
  let events = [Opened(config), BidAccepted(bid), AuctionClosed(Some(bid))]
  let state = auction.fold(events)
  assert history.validate(events) == Ok(state)
}

pub fn valid_extended_history_passes_test() {
  let config =
    Config(
      ..sample_config(),
      ends_at: 60_000,
      snipe_window_ms: 10_000,
      extension_ms: 10_000,
      max_extensions: 1,
      reserve: None,
    )
  let bid = Bid("req-1", "bidder_1", 1000, 55_000)
  let events = [
    Opened(config),
    BidAccepted(bid),
    Extended(65_000),
    AuctionClosed(Some(bid)),
  ]
  let state = auction.fold(events)
  assert history.validate(events) == Ok(state)
}
