defmodule ServerPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/liveness" do
    conn = put_resp_content_type(conn, "text/plain")

    case Healthchecks.liveness() do
      :ok ->
        conn
        |> send_resp(200, "OK")

      {:error, message} ->
        conn
        |> send_resp(500, message)
    end
  end

  get "/readiness" do
    conn = put_resp_content_type(conn, "text/plain")

    case Healthchecks.readiness() do
      :ok ->
        conn
        |> send_resp(200, "OK")

      {:error, message} ->
        conn
        |> send_resp(500, message)
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
