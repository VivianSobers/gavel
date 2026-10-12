# gavel

gavel is a clustered realtime auction service written in Elixir and Gleam. Each open auction runs as its own Erlang process, and bidders follow a live bid ladder in the browser. Any app node can be killed while auctions are running; the surviving nodes take over its auctions and rebuild them from the bid log.

Status: early. The toolchain, the Phoenix app and the Gleam rules package are in place. The auction rules, clustering and web UI are being built.

## Guarantees

When finished, gavel promises the following, and a checker that runs after every chaos test verifies them:

1. A bid is acknowledged as accepted only after its event is committed to Postgres.
2. Each auction's log is a single ordered sequence `seq = 1..n` with no gaps.
3. A client request id appears at most once in the log. A retried request gets the original outcome back.
4. Replaying an auction's log through the rules core accepts every event, so the log is a valid history under the rules.
5. Every auction whose end time has passed gets exactly one close event. It is the last event, and the winner is the highest bid if the reserve is met.

Postgres provides durability and ordering through a sequence fence on each auction's log. The BEAM side handles availability, serialized validation of each auction's bids, close timers and fan-out to watchers.

## Requirements

- Docker with Docker Compose
- make

Elixir, Erlang and Gleam run inside the dev image, so nothing else needs installing.

## Quickstart

```sh
make image   # build the dev toolchain image
make check   # format checks, lint, Gleam tests and Elixir tests against Postgres
```
