import gavel_rules
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn version_test() {
  assert gavel_rules.version() == "0.1.0"
}
