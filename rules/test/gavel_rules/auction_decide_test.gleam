import gavel_rules/auction
import gavel_rules/types.{
  type Config, Bid, BidAccepted, Close, Config, Emit, NotOpen, NotYetEnded,
  Opened, PlaceBid,
}
import gleam/dict
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

pub fn first_bid_at_starting_price_accepted_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, 10_000)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1000, 10_000))]))
}

pub fn bid_above_starting_price_accepted_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1500)

  assert auction.decide(state, command, 10_000)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1500, 10_000))]))
}

pub fn second_bid_at_minimum_next_bid_accepted_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid1)])

  assert auction.minimum_next_bid(state) == 1100

  let command = PlaceBid(request_id: "req-2", bidder: "charlie", amount: 1100)
  assert auction.decide(state, command, 20_000)
    == Ok(Emit([BidAccepted(Bid("req-2", "charlie", 1100, 20_000))]))
}

pub fn folded_state_has_new_high_bid_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let bid2 = Bid("req-2", "charlie", 1100, 20_000)

  let state =
    auction.fold([Opened(config), BidAccepted(bid1), BidAccepted(bid2)])

  assert state.high_bid == Some(bid2)
  assert state.bids == [bid2, bid1]
  assert state.accepted == dict.from_list([#("req-1", bid1), #("req-2", bid2)])
  assert state.seq == 3
}

pub fn pending_auction_rejects_bid_test() {
  let state = auction.new()
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, 10_000) == Error(NotOpen)
}

pub fn close_returns_not_yet_ended_placeholder_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])

  assert auction.decide(state, Close, 10_000) == Error(NotYetEnded)
}
