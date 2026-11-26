defmodule ForcedLoad.HelpersTest do
    use ExUnit.Case, async: false

    alias ForcedLoad.Helpers

    describe "validate_direct_load!/1" do
        test "a no-op when :bigquery_direct_load is false or absent — never touches Postgres/GCS" do
            assert Helpers.validate_direct_load!(%{}) == :ok
            assert Helpers.validate_direct_load!(%{bigquery_direct_load: false}) == :ok
        end

        test "raises on an invalid bigquery_tables_by_type, before touching any connection" do
            assert_raise ArgumentError, ~r/bigquery_tables_by_type inválido/, fn ->
                Helpers.validate_direct_load!(%{bigquery_direct_load: true, bigquery_tables_by_type: []})
            end

            assert_raise ArgumentError, ~r/bigquery_tables_by_type inválido/, fn ->
                Helpers.validate_direct_load!(%{bigquery_direct_load: true, bigquery_tables_by_type: [{"a", 1}]})
            end
        end

        test "raises when gcs_bucket/gcs_credentials/postgres_temp_table are missing" do
            base = %{bigquery_direct_load: true, bigquery_tables_by_type: [{"expediente", "p.d.t"}]}

            assert_raise ArgumentError, ~r/gcs_bucket es obligatorio/, fn ->
                Helpers.validate_direct_load!(base)
            end

            assert_raise ArgumentError, ~r/gcs_credentials es obligatorio/, fn ->
                Helpers.validate_direct_load!(Map.put(base, :gcs_bucket, "bucket"))
            end
        end

        test "raises on a non-positive postgres_export_batch_size" do
            base = %{
                bigquery_direct_load: true,
                bigquery_tables_by_type: [{"expediente", "p.d.t"}],
                gcs_bucket: "b",
                gcs_credentials: "creds",
                postgres_temp_table: "t",
                postgres_export_batch_size: 0
            }

            assert_raise ArgumentError, ~r/postgres_export_batch_size inválido/, fn ->
                Helpers.validate_direct_load!(base)
            end
        end

        test "raises on a non-positive queue_stall_timeout" do
            base = %{
                bigquery_direct_load: true,
                bigquery_tables_by_type: [{"expediente", "p.d.t"}],
                gcs_bucket: "b",
                gcs_credentials: "creds",
                postgres_temp_table: "t",
                queue_stall_timeout: -1
            }

            assert_raise ArgumentError, ~r/queue_stall_timeout inválido/, fn ->
                Helpers.validate_direct_load!(base)
            end
        end
    end

    describe "get_from_app_config/2" do
        setup do
            Application.put_env(:etl_core_test_app, :nodeservice, url: "http://x", headers: [{"a", "b"}])
            on_exit(fn -> Application.delete_env(:etl_core_test_app, :nodeservice) end)
        end

        test "an empty path returns the whole top-level value" do
            assert Helpers.get_from_app_config(:etl_core_test_app, [:nodeservice]) == [url: "http://x", headers: [{"a", "b"}]]
        end

        test "a deeper path descends with get_in/2" do
            assert Helpers.get_from_app_config(:etl_core_test_app, [:nodeservice, :url]) == "http://x"
        end
    end

    describe "get_ticket_config/1 and friends" do
        test "an explicit :ticket_config short-circuits any path resolution" do
            explicit = %{url: "u", headers: [], username: "x", password: "y"}
            assert Helpers.get_ticket_config(%{ticket_config: explicit}) == explicit
        end

        test "falls back to resolving from Application config via the default paths" do
            Application.put_env(:etl_core_test_app, :ticket, url: "http://ticket")
            Application.put_env(:etl_core_test_app, :user, totalcheck: %{username: "u", password: "p"})
            on_exit(fn ->
                Application.delete_env(:etl_core_test_app, :ticket)
                Application.delete_env(:etl_core_test_app, :user)
            end)

            config = Helpers.get_ticket_config(%{app_name: :etl_core_test_app})
            assert config.url == "http://ticket"
            assert config.username == "u"
            assert config.password == "p"
        end
    end

    describe "notify/3" do
        test "dispatches to a custom notification_fn when provided, instead of the default" do
            test_pid = self()
            custom_fn = fn message, level -> send(test_pid, {:notified, message, level}) end

            Helpers.notify(%{notification_fn: custom_fn}, "hello", :info)
            assert_received {:notified, "hello", :info}
        end

        test "with no custom fn and no Slack webhook configured, just logs (no crash)" do
            assert Helpers.default_notify(%{}, "hello", :info) == :ok
        end
    end
end
