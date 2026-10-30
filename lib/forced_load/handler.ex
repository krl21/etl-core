
defmodule ForcedLoad.Handler do
    @moduledoc """
    Handler module for forced load operations.

    Provides flexible, configurable logic for historical data loading from
    BigQuery/ElasticSearch and publishing to RabbitMQ queues.

    ## Configuration Options

    The handler accepts a config map with the following keys:

    ### Required
        - `:app_name` - Atom. Application name for config lookup (e.g., :etl_leasing)
        - `:business_name` - String. Human-readable name for notifications (e.g., "LEASING")
        - `:documentary_type` - String. Document type for ElasticSearch/WorkflowService
        - `:record_queue` - String. Queue name for record messages
        - `:task_queue` - String. Queue name for task messages

    ### Required - Field Identifiers (for BigQuery/ElasticSearch queries)
        - `:bigquery_table` - String. Full BigQuery table name (e.g., "dataset.table")
        - `:unique_id_field` - Atom. Field name for unique ID in BigQuery (e.g., :unique_id)
        - `:unique_id_payload_field` - String. Field name for unique ID in ElasticSearch/payload (e.g., "uniqueId")
        - `:last_update_field` - Atom. Field name for last update timestamp in BigQuery (e.g., :ultima_actualizacion)
        - `:last_update_payload_field` - String. Field name for last update in ElasticSearch (e.g., "lastUpdate")

    ### Optional - Data Sources
        You can provide the config directly or customize the path to resolve from Application config.

        Direct config (takes precedence):
        - `:bigquery_config` - Keyword list. BigQuery ODBC config
        - `:elasticsearch_config` - Map with :url and :headers
        - `:amqp_config` - Keyword list. AMQP connection config
        - `:ticket_config` - Map with :url, :headers, :username, :password
        - `:nodeservice_config` - Map with :url and :headers
        - `:workflowservice_config` - Map with :url and :headers

        Path customization (list of atoms to index into Application config):
        - `:bigquery_path` - Default: [:bigquery]
        - `:elasticsearch_url_path` - Default: [:elasticsearch, :url]
        - `:elasticsearch_headers_path` - Default: [:elasticsearch, :headers]
        - `:amqp_path` - Default: [:my_amqp_client, :connection]
        - `:ticket_url_path` - Default: [:ticket, :url]
        - `:ticket_headers_path` - Default: [:ticket, :headers]
        - `:ticket_username_path` - Default: [:user, :totalcheck, :username]
        - `:ticket_password_path` - Default: [:user, :totalcheck, :password]
        - `:nodeservice_url_path` - Default: [:nodeservice, :url]
        - `:nodeservice_headers_path` - Default: [:nodeservice, :headers]
        - `:workflowservice_url_path` - Default: [:workflowservice, :url]
        - `:workflowservice_headers_path` - Default: [:workflowservice, :headers]

    ### Optional - Filters
        - `:id_filter` - Function. `(list_of_ids) -> filtered_list`. Filter IDs after fetching
        - `:task_name_filter` - List of Strings | nil. Filter tasks by name
        - `:record_filter` - Function. `(record_payload) -> boolean`. Filter individual records

    ### Optional - Callbacks
        - `:on_batch_start` - Function. `(batch, batch_number) -> :ok`. Called before processing each batch
        - `:on_batch_end` - Function. `(batch, batch_number, results) -> :ok`. Called after processing each batch
        - `:on_record_success` - Function. `(unique_id, payload) -> :ok`. Called after successful record load
        - `:on_record_error` - Function. `(unique_id, error) -> :ok`. Called on record load error
        - `:on_task_success` - Function. `(contentref, tasks) -> :ok`. Called after successful task load
        - `:on_task_error` - Function. `(contentref, error) -> :ok`. Called on task load error

    ### Optional - Custom Functions
        - `:get_ids_fn` - Function. `(start_date, end_date, bq_pid, config) -> list`. Custom BigQuery ID fetcher
        - `:get_ids_es_fn` - Function. `(start_date, end_date, config) -> list`. Custom ElasticSearch ID fetcher
        - `:load_record_fn` - Function. `(unique_id, ticket, channel, config) -> :ok | {:error, reason}`. Custom record loader
        - `:load_task_fn` - Function. `(contentref, ticket, channel, config) -> :ok | {:error, reason}`. Custom task loader
        - `:build_record_message_fn` - Function. `(payload) -> map`. Custom record message builder
        - `:build_task_message_fn` - Function. `(task) -> map`. Custom task message builder

    ### Optional - Behavior
        - `:time_step` - Integer. Days per interval for splitting date range (default: 7)
        - `:batch_size` - Integer. Records per batch (default: 200)
        - `:batch_delay` - Integer. Milliseconds to wait between batches (default: 0)
        - `:includes_record` - Boolean. Load records (default: true)
        - `:includes_task` - Boolean. Load tasks (default: true)
        - `:skip_elasticsearch` - Boolean. Skip ElasticSearch queries (default: false)
        - `:skip_bigquery` - Boolean. Skip BigQuery queries (default: false)
        - `:notification_fn` - Function. `(message, level) -> :ok`. Custom notification function

    ### Optional - Direct load to BigQuery via GCS
        When the forced load ends, it loads into BigQuery the records of the temporary Postgres table, through files uploaded to GCS: waits for the used queues to be empty (up to 5 minutes), writes the pending records of each type to a JSONL file in `:files_path` and deletes them from Postgres, uploads the files to GCS and loads them into their BigQuery tables.
        - `:bigquery_direct_load` - Boolean. Enables the direct load (default: false)
        - `:bigquery_tables_by_type` - List of `{type, table}`. BigQuery table of each record type (default: [])
        - `:postgres_pool` - Atom. Name of the `Pool.Postgres` pool (default: :postgres_pool)
        - `:postgres_temp_table` - String. Temporary Postgres table with the records. Required if the direct load is enabled
        - `:postgres_export_batch_size` - Integer. Records read, written to the file and deleted from Postgres per batch (default: 10000)
        - `:files_path` - String. Local directory where the record files are written (default: "./tmp")
        - `:gcs_bucket` - String. Bucket where the files are uploaded. Required if the direct load is enabled
        - `:gcs_folder` - String | nil. Folder of the bucket. With nil or "", the files are uploaded to the root of the bucket
        - `:gcs_credentials_path` - String. Service account JSON credentials for GCS and BigQuery. Required if the direct load is enabled

    ## Example Usage

    ```elixir
    config = %{
        app_name: :etl_leasing,
        business_name: "LEASING",
        documentary_type: "leasing_doc",
        record_queue: "leasing.record",
        task_queue: "leasing.task",

        # Field identifiers
        bigquery_table: "dataset.records",
        unique_id_field: :unique_id,
        unique_id_payload_field: "uniqueId",
        last_update_field: :ultima_actualizacion,
        last_update_payload_field: "lastUpdate",

        # Time and loading settings
        time_step: 7,
        includes_record: true,
        includes_task: true,

        # Optional filters
        task_name_filter: ["task_1", "task_2"],
        batch_size: 100
    }

    # params only contains [start_date, end_date]
    ForcedLoad.Handler.run(:record, [start_date, end_date], config)
    ```
    """

    require Logger
    alias Connection.Odbc
    alias ForcedLoad.Helpers
    alias ForcedLoad.Handler.DirectLoad
    alias ForcedLoad.Handler.Loader
    import Time.Timem, only: [by_intervals: 3]


    # ============================================
    # PUBLIC API
    # ============================================

    @doc """
    Runs the forced load process for records and/or tasks.

    ### Parameters
        - business: Atom. Business type (e.g., :record)
        - params: List. [start_date, end_date]
        - config: Map. Configuration options (see module docs)
            - :time_step - Integer. Days per interval (default: 7)
            - :includes_record - Boolean. Load records (default: true)
            - :includes_task - Boolean. Load tasks (default: true)

    ### Returns
        - :ok on success
        - {:error, reason} on failure
    """
    def run(business, params, config) do
        case business do
            :record ->
                run_record_load(params, config)

            other ->
                Logger.warning("Tipo de negocio desconocido para carga forzada: #{inspect(other)}")
                {:error, :unknown_business}
        end
    end


    @doc """
    Runs record/task forced load with the given parameters and configuration.

    ### Parameters
        - params: List. [start_date, end_date]
        - config: Map. Configuration options with:
            - :time_step - Integer. Days per interval (default: 7)
            - :includes_record - Boolean. Load records (default: true)
            - :includes_task - Boolean. Load tasks (default: true)

    ### Returns
        - :ok on success
    """
    def run_record_load([start_date, end_date], config) do
        start_date = Timex.to_datetime(start_date)
        end_date = Timex.to_datetime(end_date)

        step = Map.get(config, :time_step, 7)
        includes_record = Map.get(config, :includes_record, true)
        includes_task = Map.get(config, :includes_task, true)

        business_name = Map.get(config, :business_name, "UNKNOWN")

        Helpers.notify(config,
            """
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            CARGA FORZADA. #{business_name}
            Período: #{to_string(start_date)} - #{to_string(end_date)}
            Carga de expedientes: #{to_string(includes_record)}
            Carga de tareas asociadas a los expedientes: #{to_string(includes_task)}
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            """,
            :info
        )

        {:ok, intervals} = by_intervals(start_date, end_date, step)

        # Open AMQP connection
        amqp_config = Helpers.get_amqp_config(config)
        {:ok, connection} = AMQP.Connection.open(amqp_config)
        {:ok, channel} = AMQP.Channel.open(connection)

        bq_pid = unless Map.get(config, :skip_bigquery, false) do
            bq_config = Helpers.get_bigquery_config(config)
            Helpers.notify(config, "Abriendo conexión a BigQuery...", :info)
            Odbc.connect(bq_config)
        end

        try do
            # The BigQuery connection is only used to fetch the IDs: it is closed before the direct load
            try do
                intervals
                |> Enum.each(fn {start_date_, end_date_} ->
                    Loader.process_interval(
                        start_date_,
                        end_date_,
                        channel,
                        bq_pid,
                        includes_record,
                        includes_task,
                        config
                    )
                end)
            after
                if bq_pid do
                    Helpers.notify(config, "Cerrando conexión a BigQuery...", :info)
                    Odbc.disconnect(bq_pid)
                end
            end

            if Map.get(config, :bigquery_direct_load, false) do
                DirectLoad.run(channel, includes_record, includes_task, config)
            end

            Helpers.notify(config,
                """
                *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
                CARGA FORZADA. #{business_name}
                Período: #{to_string(start_date)} - #{to_string(end_date)}.
                FIN!!!
                *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
                """,
                :info
            )
            :ok
        after
            # Close AMQP connection
            if connection, do: AMQP.Connection.close(connection)
        end
    end


end
