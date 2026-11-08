defmodule GavelWeb.FormatTest do
  use ExUnit.Case, async: true

  alias GavelWeb.Format

  describe "money/1" do
    test "formats cents as dollars" do
      assert Format.money(1_250) == "$12.50"
      assert Format.money(5) == "$0.05"
      assert Format.money(0) == "$0.00"
      assert Format.money(100_000) == "$1,000.00"
      assert Format.money(123_456_789) == "$1,234,567.89"
    end
  end

  describe "parse_money/1" do
    test "reads dollars with up to two decimals" do
      assert Format.parse_money("12") == {:ok, 1_200}
      assert Format.parse_money("12.5") == {:ok, 1_250}
      assert Format.parse_money("12.50") == {:ok, 1_250}
      assert Format.parse_money("0.05") == {:ok, 5}
      assert Format.parse_money(" 7.01 ") == {:ok, 701}
    end

    test "never loses a cent to floating point" do
      assert Format.parse_money("1.15") == {:ok, 115}
      assert Format.parse_money("4.35") == {:ok, 435}
    end

    test "rejects anything else" do
      for input <- ["", "abc", "-1", "1.234", "1.", ".5", "1,000", "1e3"] do
        assert Format.parse_money(input) == :error, "expected #{inspect(input)} to be rejected"
      end
    end
  end

  describe "remaining/1" do
    test "formats a duration, rounding partial seconds up" do
      assert Format.remaining(1) == "1s"
      assert Format.remaining(45_000) == "45s"
      assert Format.remaining(725_000) == "12m 05s"
      assert Format.remaining(3_723_000) == "1h 02m 03s"
      assert Format.remaining(183_600_000) == "2d 03h"
    end

    test "reports a passed end time" do
      assert Format.remaining(0) == "Ended"
      assert Format.remaining(-5_000) == "Ended"
    end
  end
end
