import gavel_rules/auction
import gavel_rules/types.{
  type Config, Config, InvalidConfig, Opened, Pending, State,
}
import gleam/dict
import gleam/option.{None, Some}

fn valid_config() -> Config {
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

pub fn new_auction_test() {
  assert auction.new() == State(None, Pending, None, [], dict.new(), 0, 0, 0)
}

pub fn open_valid_config_test() {
  let config = valid_config()
  assert auction.open(config) == Ok([Opened(config)])
}

pub fn open_valid_config_without_reserve_test() {
  let config = Config(..valid_config(), reserve: None)
  assert auction.open(config) == Ok([Opened(config)])
}

pub fn open_valid_config_zero_sniping_test() {
  let config =
    Config(
      ..valid_config(),
      snipe_window_ms: 0,
      extension_ms: 0,
      max_extensions: 0,
    )
  assert auction.open(config) == Ok([Opened(config)])
}

pub fn reject_empty_title_test() {
  let config = Config(..valid_config(), title: "")
  assert auction.open(config) == Error(InvalidConfig("title"))
}

pub fn reject_empty_seller_test() {
  let config = Config(..valid_config(), seller: "")
  assert auction.open(config) == Error(InvalidConfig("seller"))
}

pub fn reject_starting_price_zero_test() {
  let config = Config(..valid_config(), starting_price: 0)
  assert auction.open(config) == Error(InvalidConfig("starting_price"))
}

pub fn reject_starting_price_negative_test() {
  let config = Config(..valid_config(), starting_price: -100)
  assert auction.open(config) == Error(InvalidConfig("starting_price"))
}

pub fn reject_reserve_zero_test() {
  let config = Config(..valid_config(), reserve: Some(0))
  assert auction.open(config) == Error(InvalidConfig("reserve"))
}

pub fn reject_reserve_negative_test() {
  let config = Config(..valid_config(), reserve: Some(-500))
  assert auction.open(config) == Error(InvalidConfig("reserve"))
}

pub fn reject_ends_at_zero_test() {
  let config = Config(..valid_config(), ends_at: 0)
  assert auction.open(config) == Error(InvalidConfig("ends_at"))
}

pub fn reject_ends_at_negative_test() {
  let config = Config(..valid_config(), ends_at: -1000)
  assert auction.open(config) == Error(InvalidConfig("ends_at"))
}

pub fn reject_snipe_window_negative_test() {
  let config = Config(..valid_config(), snipe_window_ms: -1)
  assert auction.open(config) == Error(InvalidConfig("snipe_window_ms"))
}

pub fn reject_extension_ms_negative_test() {
  let config = Config(..valid_config(), extension_ms: -1)
  assert auction.open(config) == Error(InvalidConfig("extension_ms"))
}

pub fn reject_max_extensions_negative_test() {
  let config = Config(..valid_config(), max_extensions: -1)
  assert auction.open(config) == Error(InvalidConfig("max_extensions"))
}

pub fn order_title_before_seller_test() {
  let config = Config(..valid_config(), title: "", seller: "")
  assert auction.open(config) == Error(InvalidConfig("title"))
}

pub fn order_seller_before_starting_price_test() {
  let config = Config(..valid_config(), seller: "", starting_price: 0)
  assert auction.open(config) == Error(InvalidConfig("seller"))
}

pub fn order_starting_price_before_reserve_test() {
  let config = Config(..valid_config(), starting_price: 0, reserve: Some(0))
  assert auction.open(config) == Error(InvalidConfig("starting_price"))
}

pub fn order_reserve_before_ends_at_test() {
  let config = Config(..valid_config(), reserve: Some(0), ends_at: 0)
  assert auction.open(config) == Error(InvalidConfig("reserve"))
}

pub fn order_ends_at_before_snipe_window_test() {
  let config = Config(..valid_config(), ends_at: 0, snipe_window_ms: -1)
  assert auction.open(config) == Error(InvalidConfig("ends_at"))
}

pub fn order_snipe_window_before_extension_ms_test() {
  let config = Config(..valid_config(), snipe_window_ms: -1, extension_ms: -1)
  assert auction.open(config) == Error(InvalidConfig("snipe_window_ms"))
}

pub fn order_extension_ms_before_max_extensions_test() {
  let config = Config(..valid_config(), extension_ms: -1, max_extensions: -1)
  assert auction.open(config) == Error(InvalidConfig("extension_ms"))
}
