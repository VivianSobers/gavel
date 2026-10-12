HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
export HOST_UID HOST_GID
DC  := docker compose
RUN := $(DC) run --rm dev

.PHONY: image toolchain mix gleam

image:
	$(DC) build dev

toolchain: image
	$(RUN) sh -c 'elixir --version && gleam --version'

mix:
	$(RUN) mix $(ARGS)

gleam:
	$(RUN) sh -c 'cd rules && gleam $(ARGS)'
