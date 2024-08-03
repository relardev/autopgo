defmodule ServerPlug do
  import Plug.Conn

  def init(options) do
    dbg()
    # initialize options
    options
  end

  def call(conn, _opts) do
    dbg()
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Hello world")
  end
end
