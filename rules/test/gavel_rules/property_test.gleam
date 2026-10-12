import gavel_rules/support/gen
import gavel_rules/types.{Emit}
import gleam/list
import qcheck

pub fn run_sanity_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  let total_emitted =
    list.fold(history, 0, fn(acc, step) {
      let #(_before, _command, _now, outcome, _after) = step
      case outcome {
        Ok(Emit(events)) -> acc + list.length(events)
        _ -> acc
      }
    })
  let final_seq = case list.last(history) {
    Ok(#(_before, _command, _now, _outcome, after)) -> after.seq
    Error(_) -> 1
  }
  assert final_seq == 1 + total_emitted
}
