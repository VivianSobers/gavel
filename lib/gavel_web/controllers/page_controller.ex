defmodule GavelWeb.PageController do
  use GavelWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
