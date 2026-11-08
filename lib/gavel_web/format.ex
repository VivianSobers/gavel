defmodule GavelWeb.Format do
  @moduledoc """
  Converts money and durations between stored values and what people read and type.
  """

  @doc """
  Formats an amount in cents as dollars.
  """
  @spec money(integer()) :: String.t()
  def money(cents) when is_integer(cents) do
    dollars =
      cents
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "$#{dollars}.#{pad(rem(cents, 100))}"
  end

  @doc """
  Reads a dollar amount with up to two decimals into cents.
  """
  @spec parse_money(String.t()) :: {:ok, non_neg_integer()} | :error
  def parse_money(input) when is_binary(input) do
    case Regex.run(~r/\A(\d+)(?:\.(\d{1,2}))?\z/, String.trim(input)) do
      [_, dollars] -> {:ok, to_cents(dollars, "")}
      [_, dollars, fraction] -> {:ok, to_cents(dollars, fraction)}
      nil -> :error
    end
  end

  @doc """
  Formats a remaining duration in milliseconds, rounding partial seconds up.
  """
  @spec remaining(integer()) :: String.t()
  def remaining(ms) when ms <= 0, do: "Ended"

  def remaining(ms) do
    total_seconds = div(ms + 999, 1_000)
    days = div(total_seconds, 86_400)
    hours = total_seconds |> rem(86_400) |> div(3_600)
    minutes = total_seconds |> rem(3_600) |> div(60)
    seconds = rem(total_seconds, 60)

    cond do
      days > 0 -> "#{days}d #{pad(hours)}h"
      hours > 0 -> "#{hours}h #{pad(minutes)}m #{pad(seconds)}s"
      minutes > 0 -> "#{minutes}m #{pad(seconds)}s"
      true -> "#{seconds}s"
    end
  end

  defp to_cents(dollars, fraction) do
    String.to_integer(dollars) * 100 + String.to_integer(String.pad_trailing(fraction, 2, "0"))
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
