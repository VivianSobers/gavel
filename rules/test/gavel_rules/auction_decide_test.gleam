import gavel_rules/auction
import gavel_rules/types.{
  type Config, AlreadyHighBidder, AuctionClosed, BelowMinimum, Bid, BidAccepted,
  Close, Config, Duplicate, Emit, Extended, InvalidAmount, NotOpen, NotYetEnded,
  Opened, PlaceBid, SellerCannotBid, TooLate,
}
import gleam/dict
import gleam/option.{None, Some}

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

pub fn bid_one_cent_below_starting_price_rejected_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 999)

  assert auction.decide(state, command, 10_000) == Error(BelowMinimum(1000))
}

pub fn bid_one_cent_below_minimum_with_high_bid_rejected_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid1)])

  assert auction.minimum_next_bid(state) == 1100

  let command = PlaceBid(request_id: "req-2", bidder: "charlie", amount: 1099)
  assert auction.decide(state, command, 20_000) == Error(BelowMinimum(1100))
}

pub fn bid_zero_amount_rejected_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 0)

  assert auction.decide(state, command, 10_000) == Error(InvalidAmount)
}

pub fn bid_negative_amount_rejected_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: -1)

  assert auction.decide(state, command, 10_000) == Error(InvalidAmount)
}

pub fn seller_cannot_bid_on_own_auction_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "alice", amount: 1000)

  assert auction.decide(state, command, 10_000) == Error(SellerCannotBid)
}

pub fn seller_cannot_bid_even_with_existing_high_bid_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid1)])
  let command = PlaceBid(request_id: "req-2", bidder: "alice", amount: 1100)

  assert auction.decide(state, command, 20_000) == Error(SellerCannotBid)
}

pub fn high_bidder_cannot_raise_own_bid_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid1)])
  let command = PlaceBid(request_id: "req-2", bidder: "bob", amount: 1100)

  assert auction.decide(state, command, 20_000) == Error(AlreadyHighBidder)
}

pub fn outbid_bidder_can_bid_again_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let bid2 = Bid("req-2", "charlie", 1100, 20_000)
  let state =
    auction.fold([Opened(config), BidAccepted(bid1), BidAccepted(bid2)])
  let command = PlaceBid(request_id: "req-3", bidder: "bob", amount: 1200)

  assert auction.decide(state, command, 30_000)
    == Ok(Emit([BidAccepted(Bid("req-3", "bob", 1200, 30_000))]))
}

pub fn bid_just_before_end_time_accepted_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, state.ends_at - 1)
    == Ok(
      Emit([
        BidAccepted(Bid("req-1", "bob", 1000, state.ends_at - 1)),
        Extended(state.ends_at - 1 + config.extension_ms),
      ]),
    )
}

pub fn bid_at_end_time_rejected_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, state.ends_at) == Error(TooLate)
}

pub fn bid_after_end_time_rejected_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, state.ends_at + 1000) == Error(TooLate)
}

pub fn same_request_twice_returns_duplicate_test() {
  let config = sample_config(1000)
  let bid = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, 15_000) == Ok(Duplicate(bid))
}

pub fn same_request_with_different_amount_returns_duplicate_test() {
  let config = sample_config(1000)
  let bid = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 2000)

  assert auction.decide(state, command, 15_000) == Ok(Duplicate(bid))
}

pub fn same_request_after_later_bid_returns_duplicate_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let bid2 = Bid("req-2", "charlie", 1100, 20_000)
  let state =
    auction.fold([Opened(config), BidAccepted(bid1), BidAccepted(bid2)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)

  assert auction.decide(state, command, 30_000) == Ok(Duplicate(bid1))
}

pub fn bid_just_inside_snipe_window_extends_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  let now = state.ends_at - config.snipe_window_ms

  assert auction.decide(state, command, now)
    == Ok(
      Emit([
        BidAccepted(Bid("req-1", "bob", 1000, now)),
        Extended(now + config.extension_ms),
      ]),
    )
}

pub fn bid_just_outside_snipe_window_does_not_extend_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  let now = state.ends_at - config.snipe_window_ms - 1

  assert auction.decide(state, command, now)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1000, now))]))
}

pub fn extension_never_shortens_test() {
  let config =
    Config(..sample_config(1000), snipe_window_ms: 60_000, extension_ms: 30_000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  // now is 50s before ends_at, inside the 60s window.
  // now + extension_ms = ends_at - 50s + 30s = ends_at - 20s <= ends_at.
  let now = state.ends_at - 50_000

  assert auction.decide(state, command, now)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1000, now))]))
}

pub fn extension_equal_to_ends_at_does_not_extend_test() {
  let config =
    Config(..sample_config(1000), snipe_window_ms: 60_000, extension_ms: 30_000)
  let state = auction.fold([Opened(config)])
  let command = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  // now + extension_ms == state.ends_at
  let now = state.ends_at - 30_000

  assert auction.decide(state, command, now)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1000, now))]))
}

pub fn third_late_bid_with_max_extensions_two_accepted_without_extension_test() {
  let config =
    Config(
      ..sample_config(1000),
      ends_at: 1_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 120_000,
      max_extensions: 2,
    )
  let state0 = auction.fold([Opened(config)])

  // First late bid at 950_000: extends by 120_000 from now to 1_070_000.
  let cmd1 = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  let bid1 = Bid("req-1", "bob", 1000, 950_000)
  assert auction.decide(state0, cmd1, 950_000)
    == Ok(Emit([BidAccepted(bid1), Extended(1_070_000)]))

  let state1 =
    auction.fold([Opened(config), BidAccepted(bid1), Extended(1_070_000)])
  assert state1.extensions_used == 1
  assert state1.ends_at == 1_070_000

  // Second late bid at 1_020_000: inside window (1_070_000 - 1_020_000 = 50_000 <= 60_000).
  // Extends by 120_000 from now to 1_140_000.
  let cmd2 = PlaceBid(request_id: "req-2", bidder: "charlie", amount: 1100)
  let bid2 = Bid("req-2", "charlie", 1100, 1_020_000)
  assert auction.decide(state1, cmd2, 1_020_000)
    == Ok(Emit([BidAccepted(bid2), Extended(1_140_000)]))

  let state2 =
    auction.fold([
      Opened(config),
      BidAccepted(bid1),
      Extended(1_070_000),
      BidAccepted(bid2),
      Extended(1_140_000),
    ])
  assert state2.extensions_used == 2
  assert state2.ends_at == 1_140_000

  // Third late bid at 1_100_000: inside window (1_140_000 - 1_100_000 = 40_000 <= 60_000).
  // extensions_used (2) >= max_extensions (2), so accepted without extension.
  let cmd3 = PlaceBid(request_id: "req-3", bidder: "bob", amount: 1200)
  let bid3 = Bid("req-3", "bob", 1200, 1_100_000)
  assert auction.decide(state2, cmd3, 1_100_000)
    == Ok(Emit([BidAccepted(bid3)]))
}

pub fn late_bid_with_max_extensions_zero_accepted_without_extension_test() {
  let config =
    Config(
      ..sample_config(1000),
      ends_at: 1_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 120_000,
      max_extensions: 0,
    )
  let state = auction.fold([Opened(config)])
  let cmd = PlaceBid(request_id: "req-1", bidder: "bob", amount: 1000)
  let now = 950_000

  assert auction.decide(state, cmd, now)
    == Ok(Emit([BidAccepted(Bid("req-1", "bob", 1000, now))]))
}

pub fn close_before_end_time_returns_not_yet_ended_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])

  assert auction.decide(state, Close, state.ends_at - 1) == Error(NotYetEnded)
}

pub fn close_at_end_time_emits_auction_closed_test() {
  let config = sample_config(1000)
  let bid = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid)])

  assert auction.decide(state, Close, state.ends_at)
    == Ok(Emit([AuctionClosed(Some(bid))]))
}

pub fn close_after_end_time_emits_auction_closed_test() {
  let config = sample_config(1000)
  let bid = Bid("req-1", "bob", 1000, 10_000)
  let state = auction.fold([Opened(config), BidAccepted(bid)])

  assert auction.decide(state, Close, state.ends_at + 1000)
    == Ok(Emit([AuctionClosed(Some(bid))]))
}

pub fn close_with_high_bid_sets_winner_test() {
  let config = sample_config(1000)
  let bid1 = Bid("req-1", "bob", 1000, 10_000)
  let bid2 = Bid("req-2", "charlie", 1100, 20_000)
  let state =
    auction.fold([Opened(config), BidAccepted(bid1), BidAccepted(bid2)])

  assert auction.decide(state, Close, state.ends_at)
    == Ok(Emit([AuctionClosed(Some(bid2))]))
}

pub fn close_with_no_bids_has_none_winner_test() {
  let config = sample_config(1000)
  let state = auction.fold([Opened(config)])

  assert auction.decide(state, Close, state.ends_at)
    == Ok(Emit([AuctionClosed(None)]))
}
