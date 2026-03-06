defmodule CotoCotoWeb.PageController do
  use CotoCotoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
