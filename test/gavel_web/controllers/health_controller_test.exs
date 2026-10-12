defmodule GavelWeb.HealthControllerTest do
  use GavelWeb.ConnCase, async: false

  defmodule DownChecker do
    @moduledoc false

    def check do
      {:error, :down}
    end
  end

  test "Gavel.Health.check/0 returns :ok when database is up" do
    assert Gavel.Health.check() == :ok
  end

  test "GET /healthz returns 200 with body ok when healthy", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert response(conn, 200) == "ok"
  end

  test "GET /healthz returns 503 with body unavailable when unhealthy", %{conn: conn} do
    previous = Application.get_env(:gavel, :health_check)

    on_exit(fn ->
      if previous do
        Application.put_env(:gavel, :health_check, previous)
      else
        Application.delete_env(:gavel, :health_check)
      end
    end)

    Application.put_env(:gavel, :health_check, DownChecker)

    conn = get(conn, ~p"/healthz")
    assert response(conn, 503) == "unavailable"
  end
end
