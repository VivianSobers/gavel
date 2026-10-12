defmodule GavelWeb.HealthController do
  use GavelWeb, :controller

  @doc """
  Responds with 200 "ok" when the database is healthy, or 503 "unavailable" otherwise.
  """
  def index(conn, _params) do
    checker = Application.get_env(:gavel, :health_check, Gavel.Health)

    case checker.check() do
      :ok ->
        text(conn, "ok")

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text("unavailable")
    end
  end
end
