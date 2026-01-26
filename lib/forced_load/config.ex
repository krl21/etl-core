
defmodule ForcedLoad.Config do
    @moduledoc """
    Behaviour and helpers for defining ForcedLoad configurations.
    ## Usage

    ```elixir
    defmodule MyApp.ForcedLoadConfig do
        use ForcedLoad.Config

        @impl true
        def app_name, do: :my_app

        @impl true
        def business_name, do: "MY APP"

        @impl true
        def documentary_type, do: "my_doc_type"

        # Path-based configuration (resolved at runtime)
        @impl true
        def record_queue_path, do: [:my_amqp_client, :queue, :record, :config, :queue]

        @impl true
        def task_queue_path, do: [:my_amqp_client, :queue, :task, :config, :queue]

        @impl true
        def bigquery_table_path, do: [:bigquery, :table, :record]

        # Field identifiers for BigQuery/ElasticSearch
        @impl true
        def unique_id_field, do: :unique_id

        @impl true
        def unique_id_payload_field, do: "uniqueId"

        @impl true
        def last_update_field, do: :ultima_actualizacion

        @impl true
        def last_update_payload_field, do: "lastUpdate"

        # Optional: Override defaults
        @impl true
        def batch_size, do: 100

        @impl true
        def time_step, do: 7

        # Optional: Webhook URL path for status notifications
        @impl true
        def webhook_url_path, do: [:notification, :slack_webhook, :url, :forced_load]
    end
    ```

    Then in application.ex:

    ```elixir
    # params only contains start_date and end_date
    # time_step, includes_record, includes_task are read from config
    {Genserver.ForcedLoad, {:record, [start_date, end_date], MyApp.ForcedLoadConfig.build_config()}}
    ```
    """

    # ============================================
    # REQUIRED CALLBACKS
    # ============================================

    @doc "Returns the application name atom"
    @callback app_name() :: atom()

    @doc "Returns the human-readable business name for notifications"
    @callback business_name() :: String.t()

    @doc "Returns the documentary type for ElasticSearch/WorkflowService"
    @callback documentary_type() :: String.t()

    # Field identifiers - Required
    @doc "Returns the field name for unique ID in BigQuery (e.g., :unique_id)"
    @callback unique_id_field() :: atom()

    @doc "Returns the field name for unique ID in ElasticSearch/payload (e.g., 'uniqueId')"
    @callback unique_id_payload_field() :: String.t()

    @doc "Returns the field name for last update timestamp in BigQuery (e.g., :ultima_actualizacion)"
    @callback last_update_field() :: atom()

    @doc "Returns the field name for last update in ElasticSearch (e.g., 'lastUpdate')"
    @callback last_update_payload_field() :: String.t()


    # ============================================
    # PATH-BASED CALLBACKS (resolved at runtime)
    # ============================================

    @doc """
    Returns the path to resolve record queue name from Application config.
    Example: [:my_amqp_client, :queue, :record, :config, :queue]
    Resolved as: Application.get_env(app_name(), :my_amqp_client)[:queue][:record][:config][:queue]
    """
    @callback record_queue_path() :: [atom()]

    @doc """
    Returns the path to resolve task queue name from Application config.
    Example: [:my_amqp_client, :queue, :task, :config, :queue]
    """
    @callback task_queue_path() :: [atom()]

    @doc """
    Returns the path to resolve BigQuery table name from Application config.
    Example: [:bigquery, :table, :record]
    """
    @callback bigquery_table_path() :: [atom()]


    # ============================================
    # OPTIONAL CALLBACKS
    # ============================================

    @doc "Returns the time step for interval splitting in days (default: 7)"
    @callback time_step() :: integer()

    @doc "Returns the batch size (default: 200)"
    @callback batch_size() :: integer()

    @doc "Returns the batch delay in milliseconds (default: 0)"
    @callback batch_delay() :: integer()

    @doc "Returns whether to load records (default: true)"
    @callback includes_record() :: boolean()

    @doc "Returns whether to load tasks (default: true)"
    @callback includes_task() :: boolean()

    @doc "Returns a function to filter IDs after fetching, or nil"
    @callback id_filter() :: (list() -> list()) | nil

    @doc "Returns a function to filter records before publishing, or nil"
    @callback record_filter() :: (map() -> boolean()) | nil

    @doc "Returns a list of task names to filter, or nil for all tasks"
    @callback task_name_filter() :: [String.t()] | nil

    @doc "Returns whether to skip ElasticSearch queries"
    @callback skip_elasticsearch() :: boolean()

    @doc "Returns whether to skip BigQuery queries"
    @callback skip_bigquery() :: boolean()

    @doc "Returns custom notification function, or nil for default"
    @callback notification_fn() :: (String.t(), atom() -> :ok) | nil


    # ============================================
    # OPTIONAL PATH-BASED CALLBACKS
    # ============================================

    @doc """
    Returns the path to resolve webhook URL from Application config, or nil to disable.
    Example: [:notification, :slack_webhook, :url, :forced_load]
    """
    @callback webhook_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve BigQuery connection config from Application config.
    Example: [:bigquery, :configuration]
    """
    @callback bigquery_config_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve ElasticSearch URL from Application config.
    Example: [:elasticsearch, :url]
    """
    @callback elasticsearch_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve ElasticSearch headers from Application config.
    Example: [:elasticsearch, :headers]
    """
    @callback elasticsearch_headers_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve AMQP connection config from Application config.
    Example: [:my_amqp_client, :connection]
    """
    @callback amqp_config_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Slack notification webhook URL from Application config.
    Example: [:notification, :slack_webhook, :url, :notification]
    """
    @callback slack_notification_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Slack notification headers from Application config.
    Example: [:notification, :slack_webhook, :headers]
    """
    @callback slack_notification_headers_path() :: [atom()] | nil

    @doc """
    Returns the environment variable name to read for environment identifier.
    Example: "ENVIRONMENT"
    """
    @callback environment_var() :: String.t() | nil

    @doc """
    Returns the path to resolve NodeService URL from Application config.
    Example: [:nodeservice, :url]
    """
    @callback nodeservice_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve NodeService headers from Application config.
    Example: [:nodeservice, :headers]
    """
    @callback nodeservice_headers_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve WorkflowService URL from Application config.
    Example: [:workflowservice, :url]
    """
    @callback workflowservice_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve WorkflowService headers from Application config.
    Example: [:workflowservice, :headers]
    """
    @callback workflowservice_headers_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Ticket URL from Application config.
    Example: [:ticket, :url]
    """
    @callback ticket_url_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Ticket headers from Application config.
    Example: [:ticket, :headers]
    """
    @callback ticket_headers_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Ticket username from Application config.
    Example: [:user, :totalcheck, :username]
    """
    @callback ticket_username_path() :: [atom()] | nil

    @doc """
    Returns the path to resolve Ticket password from Application config.
    Example: [:user, :totalcheck, :password]
    """
    @callback ticket_password_path() :: [atom()] | nil


    @optional_callbacks [
        time_step: 0,
        batch_size: 0,
        batch_delay: 0,
        includes_record: 0,
        includes_task: 0,
        id_filter: 0,
        record_filter: 0,
        task_name_filter: 0,
        skip_elasticsearch: 0,
        skip_bigquery: 0,
        notification_fn: 0,
        webhook_url_path: 0,
        bigquery_config_path: 0,
        elasticsearch_url_path: 0,
        elasticsearch_headers_path: 0,
        amqp_config_path: 0,
        slack_notification_url_path: 0,
        slack_notification_headers_path: 0,
        environment_var: 0,
        nodeservice_url_path: 0,
        nodeservice_headers_path: 0,
        workflowservice_url_path: 0,
        workflowservice_headers_path: 0,
        ticket_url_path: 0,
        ticket_headers_path: 0,
        ticket_username_path: 0,
        ticket_password_path: 0
    ]


    defmacro __using__(_opts) do
        quote do
            @behaviour ForcedLoad.Config

            # Default implementations for optional callbacks
            def time_step, do: 7
            def batch_size, do: 200
            def batch_delay, do: 0
            def includes_record, do: true
            def includes_task, do: true
            def id_filter, do: nil
            def record_filter, do: nil
            def task_name_filter, do: nil
            def skip_elasticsearch, do: false
            def skip_bigquery, do: false
            def notification_fn, do: nil
            def webhook_url_path, do: nil
            def bigquery_config_path, do: [:bigquery, :configuration]
            def elasticsearch_url_path, do: [:elasticsearch, :url]
            def elasticsearch_headers_path, do: [:elasticsearch, :headers]
            def amqp_config_path, do: [:my_amqp_client, :connection]
            def slack_notification_url_path, do: [:notification, :slack_webhook, :url, :notification]
            def slack_notification_headers_path, do: [:notification, :slack_webhook, :headers]
            def environment_var, do: "ENVIRONMENT"
            def nodeservice_url_path, do: [:nodeservice, :url]
            def nodeservice_headers_path, do: [:nodeservice, :headers]
            def workflowservice_url_path, do: [:workflowservice, :url]
            def workflowservice_headers_path, do: [:workflowservice, :headers]
            def ticket_url_path, do: [:ticket, :url]
            def ticket_headers_path, do: [:ticket, :headers]
            def ticket_username_path, do: [:user, :totalcheck, :username]
            def ticket_password_path, do: [:user, :totalcheck, :password]

            defoverridable [
                time_step: 0,
                batch_size: 0,
                batch_delay: 0,
                includes_record: 0,
                includes_task: 0,
                id_filter: 0,
                record_filter: 0,
                task_name_filter: 0,
                skip_elasticsearch: 0,
                skip_bigquery: 0,
                notification_fn: 0,
                webhook_url_path: 0,
                bigquery_config_path: 0,
                elasticsearch_url_path: 0,
                elasticsearch_headers_path: 0,
                amqp_config_path: 0,
                slack_notification_url_path: 0,
                slack_notification_headers_path: 0,
                environment_var: 0,
                nodeservice_url_path: 0,
                nodeservice_headers_path: 0,
                workflowservice_url_path: 0,
                workflowservice_headers_path: 0,
                ticket_url_path: 0,
                ticket_headers_path: 0,
                ticket_username_path: 0,
                ticket_password_path: 0
            ]

            @doc """
            Resolves a config path to its actual value from Application config.

            ### Parameters
                - path: List of atoms representing the config path

            ### Returns
                - The resolved value, or nil if not found
            """
            def resolve_config_path(nil), do: nil
            def resolve_config_path([]), do: nil
            def resolve_config_path([first | rest]) do
                case Application.get_env(app_name(), first) do
                    nil -> nil
                    config -> get_in(config, rest)
                end
            end

            @doc """
            Builds the configuration map for the ForcedLoad handler.

            All path-based configurations are resolved at call time using `Application.get_env/2`.

            ### Parameters
                - overrides: Map. Optional overrides for any config key

            ### Returns
                - Map. Complete configuration for ForcedLoad.Handler
            """
            def build_config(overrides \\ %{}) do
                base_config = %{
                    app_name: app_name(),
                    business_name: business_name(),
                    documentary_type: documentary_type(),
                    # Resolve path-based configs
                    record_queue: resolve_config_path(record_queue_path()),
                    task_queue: resolve_config_path(task_queue_path()),
                    bigquery_table: resolve_config_path(bigquery_table_path()),
                    # Field identifiers
                    unique_id_field: unique_id_field(),
                    unique_id_payload_field: unique_id_payload_field(),
                    last_update_field: last_update_field(),
                    last_update_payload_field: last_update_payload_field(),
                    # Time and batch settings
                    time_step: time_step(),
                    batch_size: batch_size(),
                    batch_delay: batch_delay(),
                    includes_record: includes_record(),
                    includes_task: includes_task()
                }

                # Add optional configs if they return non-nil
                optional_configs = [
                    {:id_filter, id_filter()},
                    {:record_filter, record_filter()},
                    {:task_name_filter, task_name_filter()},
                    {:notification_fn, notification_fn()},
                    {:webhook_url, resolve_config_path(webhook_url_path())},
                    {:bigquery_config, resolve_config_path(bigquery_config_path())},
                    {:amqp_config, resolve_config_path(amqp_config_path())},
                    {:slack_notification_url, resolve_config_path(slack_notification_url_path())},
                    {:slack_notification_headers, resolve_config_path(slack_notification_headers_path())},
                    {:environment, if(env_var = environment_var(), do: System.get_env(env_var), else: nil)}
                ]
                |> Enum.reject(fn {_key, value} -> is_nil(value) end)
                |> Enum.into(%{})

                # Add path-based configs for Handler resolvers
                path_configs = %{
                    elasticsearch_url_path: elasticsearch_url_path(),
                    elasticsearch_headers_path: elasticsearch_headers_path(),
                    nodeservice_url_path: nodeservice_url_path(),
                    nodeservice_headers_path: nodeservice_headers_path(),
                    workflowservice_url_path: workflowservice_url_path(),
                    workflowservice_headers_path: workflowservice_headers_path(),
                    ticket_url_path: ticket_url_path(),
                    ticket_headers_path: ticket_headers_path(),
                    ticket_username_path: ticket_username_path(),
                    ticket_password_path: ticket_password_path(),
                    bigquery_path: bigquery_config_path(),
                    amqp_path: amqp_config_path()
                }

                # Add boolean flags
                boolean_configs = %{
                    skip_elasticsearch: skip_elasticsearch(),
                    skip_bigquery: skip_bigquery()
                }

                base_config
                |> Map.merge(optional_configs)
                |> Map.merge(path_configs)
                |> Map.merge(boolean_configs)
                |> Map.merge(overrides)
            end

            @doc """
            Builds the parameters list for the ForcedLoad GenServer.

            ### Parameters
                - start_date: DateTime or String. Start date for the load
                - end_date: DateTime or String. End date for the load

            ### Returns
                - List. [start_date, end_date]
            """
            def build_params(start_date, end_date) do
                [start_date, end_date]
            end
        end
    end


end
