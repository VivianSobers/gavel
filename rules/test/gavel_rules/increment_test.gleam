import gavel_rules/increment

pub fn increment_at_0_test() {
  assert increment.increment(0) == 50
}

pub fn increment_at_999_test() {
  assert increment.increment(999) == 50
}

pub fn increment_at_1000_test() {
  assert increment.increment(1000) == 100
}

pub fn increment_at_9999_test() {
  assert increment.increment(9999) == 100
}

pub fn increment_at_10000_test() {
  assert increment.increment(10_000) == 500
}

pub fn increment_at_99999_test() {
  assert increment.increment(99_999) == 500
}

pub fn increment_at_100000_test() {
  assert increment.increment(100_000) == 2500
}

pub fn increment_at_5000000_test() {
  assert increment.increment(5_000_000) == 2500
}
