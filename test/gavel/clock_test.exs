defmodule Gavel.ClockTest do
  use ExUnit.Case, async: false

  alias Gavel.Clock

  describe "test double" do
    test "set then read" do
      Clock.Test.set(1_700_000_000_000)
      assert Clock.now_ms() == 1_700_000_000_000
      assert Clock.Test.now_ms() == 1_700_000_000_000
    end

    test "advance" do
      Clock.Test.set(1_000)
      assert :ok = Clock.Test.advance(500)
      assert Clock.now_ms() == 1_500
      assert Clock.Test.now_ms() == 1_500
    end
  end

  describe "system clock" do
    test "returns current system time in milliseconds" do
      now = Clock.System.now_ms()
      system_now = System.system_time(:millisecond)

      assert is_integer(now)
      assert_in_delta now, system_now, 50
    end
  end
end
