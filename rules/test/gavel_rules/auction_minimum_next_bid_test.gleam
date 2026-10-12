import gavel_rules/auction
import gavel_rules/types.{type Bid, type Config, Bid, Config, Opened, State}
import gleam/option.{Some}

fn sample_config(starting_price: Int) -> Config {
  Config(
    title: "Vintage Watch",
    seller: "alice",
    starting_price: starting_price,
    reserve: Some(5000),
    ends_at: 1_700_000_000_000,
    snipe_window_ms: 60_000,
    extension_ms: 120_000,
    max_extensions: 5,
  )
}

fn sample_bid(amount: Int) -> Bid {
  Bid(request_id: "req-1", bidder: "bob", amount: amount, at: 1_699_999_900_000)
}

pub fn minimum_next_bid_pending_state_test() {
  let state = auction.new()
  assert auction.minimum_next_bid(state) == 0
}

pub fn minimum_next_bid_no_high_bid_test() {
  let config1 = sample_config(1000)
  let state1 = auction.fold([Opened(config1)])
  assert auction.minimum_next_bid(state1) == 1000

  let config2 = sample_config(250)
  let state2 = auction.fold([Opened(config2)])
  assert auction.minimum_next_bid(state2) == 250
}

pub fn minimum_next_bid_with_high_bid_band_under_1000_test() {
  let open_state = auction.fold([Opened(sample_config(100))])

  let state_at_0 = State(..open_state, high_bid: Some(sample_bid(0)))
  assert auction.minimum_next_bid(state_at_0) == 50

  let state_at_500 = State(..open_state, high_bid: Some(sample_bid(500)))
  assert auction.minimum_next_bid(state_at_500) == 550

  let state_at_999 = State(..open_state, high_bid: Some(sample_bid(999)))
  assert auction.minimum_next_bid(state_at_999) == 1049
}

pub fn minimum_next_bid_with_high_bid_band_1000_to_9999_test() {
  let open_state = auction.fold([Opened(sample_config(1000))])

  let state_at_1000 = State(..open_state, high_bid: Some(sample_bid(1000)))
  assert auction.minimum_next_bid(state_at_1000) == 1100

  let state_at_9999 = State(..open_state, high_bid: Some(sample_bid(9999)))
  assert auction.minimum_next_bid(state_at_9999) == 10_099
}

pub fn minimum_next_bid_with_high_bid_band_10000_to_99999_test() {
  let open_state = auction.fold([Opened(sample_config(10_000))])

  let state_at_10000 = State(..open_state, high_bid: Some(sample_bid(10_000)))
  assert auction.minimum_next_bid(state_at_10000) == 10_500

  let state_at_99999 = State(..open_state, high_bid: Some(sample_bid(99_999)))
  assert auction.minimum_next_bid(state_at_99999) == 100_499
}

pub fn minimum_next_bid_with_high_bid_band_100000_and_above_test() {
  let open_state = auction.fold([Opened(sample_config(100_000))])

  let state_at_100000 = State(..open_state, high_bid: Some(sample_bid(100_000)))
  assert auction.minimum_next_bid(state_at_100000) == 102_500

  let state_at_5000000 =
    State(..open_state, high_bid: Some(sample_bid(5_000_000)))
  assert auction.minimum_next_bid(state_at_5000000) == 5_002_500
}
