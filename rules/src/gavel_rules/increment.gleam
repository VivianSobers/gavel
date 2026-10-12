import gleam/bool

pub fn increment(price: Int) -> Int {
  use <- bool.guard(price < 1000, 50)
  use <- bool.guard(price < 10_000, 100)
  use <- bool.guard(price < 100_000, 500)
  2500
}
