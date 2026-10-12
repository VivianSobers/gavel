defmodule Gavel.Clock do
  @moduledoc """
  Clock behaviour and dispatch for time retrieval in unix milliseconds.
  """

  @callback now_ms() :: integer()

  @doc """
  Returns the current time in unix milliseconds using the configured clock module.
  """
  @spec now_ms() :: integer()
  def now_ms do
    clock = Application.get_env(:gavel, :clock, Gavel.Clock.System)
    clock.now_ms()
  end
end
