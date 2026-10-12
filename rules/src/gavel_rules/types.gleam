import gleam/dict.{type Dict}
import gleam/option.{type Option}

pub type Config {
  Config(
    title: String,
    seller: String,
    starting_price: Int,
    reserve: Option(Int),
    ends_at: Int,
    snipe_window_ms: Int,
    extension_ms: Int,
    max_extensions: Int,
  )
}

pub type Bid {
  Bid(request_id: String, bidder: String, amount: Int, at: Int)
}

pub type Status {
  Pending
  Open
  Closed
}

pub type State {
  State(
    config: Option(Config),
    status: Status,
    high_bid: Option(Bid),
    bids: List(Bid),
    accepted: Dict(String, Bid),
    extensions_used: Int,
    ends_at: Int,
    seq: Int,
  )
}

pub type Command {
  PlaceBid(request_id: String, bidder: String, amount: Int)
  Close
}

pub type Event {
  Opened(config: Config)
  BidAccepted(bid: Bid)
  Extended(ends_at: Int)
  AuctionClosed(winner: Option(Bid))
}

pub type Rejection {
  InvalidConfig(reason: String)
  NotOpen
  AlreadyClosed
  TooLate
  BelowMinimum(minimum: Int)
  InvalidAmount
  SellerCannotBid
  AlreadyHighBidder
  NotYetEnded
}

pub type Decision {
  Emit(events: List(Event))
  Duplicate(bid: Bid)
}
