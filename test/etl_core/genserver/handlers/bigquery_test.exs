defmodule Genserver.Handlers.BigqueryTest do
    use ExUnit.Case, async: false

    import Mox

    setup :verify_on_exit!

    alias Genserver.Handlers.Bigquery

    defp pg_record(id, id_nodo, data) do
        %{
            id: id,
            id_nodo: id_nodo,
            tipo: "expediente",
            informacion: Poison.encode!(data),
            fecha_creado: ~U[2024-01-01 00:00:00Z],
            estado_analisis: "sin_analizar"
        }
    end

    describe "run/10 — happy path" do
        test "inserts every group's most recent record and marks them sent in Postgres" do
            records = [pg_record(1, "N1", %{"campo" => "a"}), pg_record(2, "N2", %{"campo" => "b"})]

            Connection.PostgresMock
            |> expect(:get_pending_bq, fn :pg_conn, "pg_table", "expediente", [] -> {:ok, records} end)
            |> expect(:mark_as_sent_to_bq_by_id_nodos, fn :pg_conn, "pg_table", id_nodos, "expediente" ->
                assert Enum.sort(id_nodos) == ["N1", "N2"]
                {:ok, 2}
            end)

            expect(Connection.OdbcMock, :insert, 1, fn :bq_conn, query ->
                assert query =~ "'a'"
                assert query =~ "'b'"
                {:updated, 2}
            end)

            assert Bigquery.run(:test_business, :bq_conn, :pg_conn, "pg_table", "bq_table", "expediente", "batch1", 10, "https://hook") ==
                {:ok, 2}
        end

        test "no pending records: {:ok, 0}, nothing marked in Postgres" do
            expect(Connection.PostgresMock, :get_pending_bq, fn _, _, _, _ -> {:ok, []} end)

            assert Bigquery.run(:test_business, :bq_conn, :pg_conn, "pg_table", "bq_table", "expediente", "batch1", 10, "https://hook") ==
                {:ok, 0}
        end

        test "a get_pending_bq error is reported, not raised" do
            expect(Connection.PostgresMock, :get_pending_bq, fn _, _, _, _ -> {:error, :timeout} end)

            assert Bigquery.run(:test_business, :bq_conn, :pg_conn, "pg_table", "bq_table", "expediente", "batch1", 10, "https://hook") ==
                {:error, :timeout}
        end
    end

    describe "run/10 — a group's most recent record fails to insert" do
        test "falls back to the next most recent record of the same id_nodo" do
            # N1 has a single, successful record. N2's newest record ("b_new")
            # fails to insert; the handler should fall back to N2's older
            # record ("b_old") and report N2 as successful overall, with the
            # newest N2 id recorded as a problem.
            records = [
                pg_record(1, "N1", %{"campo" => "a"}),
                pg_record(2, "N2", %{"campo" => "b_new"}),
                pg_record(3, "N2", %{"campo" => "b_old"})
            ]

            Connection.PostgresMock
            |> expect(:get_pending_bq, fn _, _, _, _ -> {:ok, records} end)
            |> expect(:mark_as_sent_to_bq_by_id_nodos, fn :pg_conn, "pg_table", id_nodos, "expediente" ->
                assert Enum.sort(id_nodos) == ["N1", "N2"]
                {:ok, 2}
            end)
            |> expect(:mark_as_with_problems, fn :pg_conn, "pg_table", failed_ids ->
                assert failed_ids == [2]
                {:ok, 1}
            end)

            Connection.OdbcMock
            |> stub(:insert, fn :bq_conn, query ->
                if query =~ "b_new" do
                    raise "simulated BigQuery failure"
                else
                    {:updated, 1}
                end
            end)

            stub(Connection.HttpMock, :post, fn _body, _url, _headers -> {:ok, %HTTPoison.Response{status_code: 200, body: "ok"}} end)

            assert Bigquery.run(:test_business, :bq_conn, :pg_conn, "pg_table", "bq_table", "expediente", "batch1", 10, "https://hook") ==
                {:ok, 2}
        end
    end
end
