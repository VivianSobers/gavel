HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
export HOST_UID HOST_GID
DC  := docker compose
RUN := $(DC) run --rm dev

.PHONY: image toolchain mix gleam gleam-test db-up db-down db-reset deps test fmt check release-image release-smoke

image:
	$(DC) build dev

toolchain: image
	$(RUN) sh -c 'elixir --version && gleam --version'

mix:
	$(RUN) mix $(ARGS)

gleam:
	$(RUN) sh -c 'cd rules && gleam $(ARGS)'

gleam-test:
	$(RUN) sh -c 'cd rules && gleam test'

db-up:
	$(DC) up -d --wait db

db-down:
	$(DC) down

db-reset:
	$(DC) down -v

deps:
	$(RUN) mix deps.get

test: db-up
	$(RUN) mix test

fmt:
	$(RUN) sh -c 'mix format && cd rules && gleam format'

check: db-up
	$(RUN) sh -c 'mix format --check-formatted && (cd rules && gleam format --check && gleam test) && mix credo --strict && mix compile --warnings-as-errors && mix test'

release-image:
	docker build -t gavel:local .

release-smoke: release-image
	out=$$(docker run --rm -e DATABASE_URL=ecto://u:p@nowhere/db -e SECRET_KEY_BASE=$$(printf '%064d' 0) gavel:local bin/gavel eval 'IO.puts(:gavel_rules.version())') && test "$$out" = "0.1.0" && echo "$$out"

