import gavel_rules/auction
import gavel_rules/types.{
  type Config, AuctionClosed, Bid, BidAccepted, Config, Extended, Open, Opened,
  State,
}
import gleam/dict
import gleam/option.{None, Some}

fn sample_config() -> Config {
  Config(
    title: "Vintage Watch",
    seller: "alice",
    starting_price: 1000,
    reserve: Some(5000),
    ends_at: 1_700_000_000_000,
    snipe_window_ms: 60_000,
    extension_ms: 120_000,
    max_extensions: 5,
  )
}

pub fn fold_empty_events_test() {
  assert auction.fold([]) == auction.new()
}

pub fn fold_opened_event_test() {
  let config = sample_config()
  let state = auction.fold([Opened(config)])

  assert state.status == Open
  assert state.seq == 1
  assert state.ends_at == config.ends_at
  assert state.config == Some(config)
  assert state.high_bid == None
  assert state.bids == []
  assert state.accepted == dict.new()
  assert state.extensions_used == 0
}

pub fn evolve_opened_event_test() {
  let config = sample_config()
  let initial = auction.new()
  let state = auction.evolve(initial, Opened(config))

  assert state
    == State(
      config: Some(config),
      status: Open,
      high_bid: None,
      bids: [],
      accepted: dict.new(),
      extensions_used: 0,
      ends_at: config.ends_at,
      seq: 1,
    )
}

pub fn evolve_extended_event_test() {
  let config = sample_config()
  let open_state = auction.evolve(auction.new(), Opened(config))
  let state = auction.evolve(open_state, Extended(1_700_000_120_000))

  assert state.ends_at == 1_700_000_120_000
  assert state.extensions_used == 1
  assert state.seq == 2
}

pub fn evolve_other_events_increment_seq_only_test() {
  let config = sample_config()
  let open_state = auction.evolve(auction.new(), Opened(config))

  let bid =
    Bid(request_id: "req-1", bidder: "bob", amount: 1500, at: 1_699_999_900_000)
  let after_bid = auction.evolve(open_state, BidAccepted(bid))
  assert after_bid.seq == 2
  assert after_bid.status == Open
  assert after_bid.ends_at == config.ends_at
  assert after_bid.config == Some(config)

  let after_extended = auction.evolve(after_bid, Extended(1_700_000_120_000))
  assert after_extended.seq == 3
  assert after_extended.status == Open
  assert after_extended.ends_at == 1_700_000_120_000
  assert after_extended.extensions_used == 1

  let after_closed = auction.evolve(after_extended, AuctionClosed(Some(bid)))
  assert after_closed.seq == 4
  assert after_closed.status == Open
}

pub fn fold_multiple_events_test() {
  let config = sample_config()
  let bid =
    Bid(request_id: "req-1", bidder: "bob", amount: 1500, at: 1_699_999_900_000)
  let state =
    auction.fold([
      Opened(config),
      BidAccepted(bid),
      Extended(1_700_000_120_000),
      AuctionClosed(Some(bid)),
    ])

  assert state.status == Open
  assert state.seq == 4
  assert state.ends_at == 1_700_000_120_000
  assert state.extensions_used == 1
  assert state.config == Some(config)
}
