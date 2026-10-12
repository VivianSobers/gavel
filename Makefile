HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
export HOST_UID HOST_GID
DC  := docker compose
RUN := $(DC) run --rm dev

.PHONY: image toolchain mix gleam gleam-test db-up db-down db-reset deps test

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

