
defmodule ForcedLoad.Helpers do
    @moduledoc """
    Helper functions for ForcedLoad.Handler.
    """

    require Logger
    alias Connection.Ticket


    @doc """
    Obtains an authentication ticket from the Ticket service.

    ### Parameters
        - config: map. Configuration with ticket service credentials

    ### Returns
        - String. Authentication ticket on success
        - nil on failure
    """
    def get_ticket(config) do
        ticket_config = get_ticket_config(config)

        try do
            Ticket.get(ticket_config.url, ticket_config.headers, ticket_config.username, ticket_config.password)
            |> case do
                {:ok, ticket} -> ticket
                {:error, error} ->
                    notify(config, "Failed to get ticket: #{inspect(error)}", :error)
                    nil
            end
        rescue
            error ->
                notify(config, "Error getting ticket: #{inspect(error)}", :error)
                nil
        end
    end


    @doc """
    Generic helper to get a value from Application config using a path of atoms.

    ### Parameters
        - app_name: atom. Application name
        - path: list. List of atoms representing the config path

    ### Returns
        - The resolved value from Application config

    ### Example
        get_from_app_config(:my_app, [:nodeservice, :url])
        => Application.get_env(:my_app, :nodeservice)[:url]
    """
    def get_from_app_config(app_name, path) when is_list(path) do
        [key | rest] = path
        app_config = Application.get_env(app_name, key)

        case rest do
            [] -> app_config
            _ -> get_in(app_config, rest)
        end
    end


    @doc """
    Resolves ticket service configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - map. Ticket config with :url, :headers, :username, :password
    """
    def get_ticket_config(config) do
        case Map.get(config, :ticket_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                %{
                    url: get_from_app_config(app_name, Map.get(config, :ticket_url_path, [:ticket, :url])),
                    headers: get_from_app_config(app_name, Map.get(config, :ticket_headers_path, [:ticket, :headers])),
                    username: get_from_app_config(app_name, Map.get(config, :ticket_username_path, [:user, :totalcheck, :username])),
                    password: get_from_app_config(app_name, Map.get(config, :ticket_password_path, [:user, :totalcheck, :password]))
                }
            ticket_config ->
                ticket_config
        end
    end


    @doc """
    Resolves NodeService configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - map. NodeService config with :url and :headers
    """
    def get_nodeservice_config(config) do
        case Map.get(config, :nodeservice_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                %{
                    url: get_from_app_config(app_name, Map.get(config, :nodeservice_url_path, [:nodeservice, :url])),
                    headers: get_from_app_config(app_name, Map.get(config, :nodeservice_headers_path, [:nodeservice, :headers]))
                }
            ns_config ->
                ns_config
        end
    end


    @doc """
    Resolves WorkflowService configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - map. WorkflowService config with :url and :headers
    """
    def get_workflowservice_config(config) do
        case Map.get(config, :workflowservice_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                %{
                    url: get_from_app_config(app_name, Map.get(config, :workflowservice_url_path, [:workflowservice, :url])),
                    headers: get_from_app_config(app_name, Map.get(config, :workflowservice_headers_path, [:workflowservice, :headers]))
                }
            ws_config ->
                ws_config
        end
    end


    @doc """
    Resolves ElasticSearch configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - map. ElasticSearch config with :url and :headers
    """
    def get_elasticsearch_config(config) do
        case Map.get(config, :elasticsearch_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                %{
                    url: get_from_app_config(app_name, Map.get(config, :elasticsearch_url_path, [:elasticsearch, :url])),
                    headers: get_from_app_config(app_name, Map.get(config, :elasticsearch_headers_path, [:elasticsearch, :headers]))
                }
            es_config ->
                es_config
        end
    end


    @doc """
    Resolves BigQuery ODBC configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - keyword. BigQuery ODBC connection config
    """
    def get_bigquery_config(config) do
        case Map.get(config, :bigquery_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                get_from_app_config(app_name, Map.get(config, :bigquery_path, [:bigquery]))
            bq_config ->
                bq_config
        end
    end


    @doc """
    Resolves AMQP connection configuration from config or Application config.

    ### Parameters
        - config: map. Handler configuration

    ### Returns
        - keyword. AMQP connection config
    """
    def get_amqp_config(config) do
        case Map.get(config, :amqp_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                get_from_app_config(app_name, Map.get(config, :amqp_path, [:my_amqp_client, :connection]))
            amqp_config ->
                amqp_config
        end
    end


    @doc """
    Sends a notification using custom function or default implementation.

    ### Parameters
        - config: map. Handler configuration (may contain :notification_fn)
        - message: String. Message to send
        - level: atom. Log level (:info, :error, :warning, :debug)
    """
    def notify(config, message, level) do
        case Map.get(config, :notification_fn) do
            nil -> default_notify(config, message, level)
            custom_fn -> custom_fn.(message, level)
        end
    end


    @doc """
    Default notification implementation: logs message and optionally sends to Slack.

    ### Parameters
        - config: map. Handler configuration with optional :slack_notification_url, :slack_notification_headers, :environment
        - message: String. Message to send
        - level: atom. Log level (:info, :error, :warning, :debug)
    """
    def default_notify(config, message, level) do
        webhook_url = Map.get(config, :slack_notification_url)
        headers = Map.get(config, :slack_notification_headers)
        environment = Map.get(config, :environment)

        if webhook_url && headers do
            Notification.Notify.notify_slack(webhook_url, headers, environment, message)
        end

        case level do
            :info -> Logger.info(message)
            :error -> Logger.error(message)
            :warning -> Logger.warning(message)
            _ -> Logger.debug(message)
        end
    end


end
