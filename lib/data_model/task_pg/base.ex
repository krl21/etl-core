
defmodule DataModel.TaskPg.Base do
    @moduledoc """
    Base module for Task entities that store data in PostgreSQL.

    Similar to `DataModel.Task.Base` but uses `Database.Postgres`
    instead of BigQuery for storage.

    ## Usage example:

        defmodule Entity.Task.Task do
            use DataModel.TaskPg.Base

            ################
            ### Entity Attributes/Columns
            ################

            @contentref %Struct.InfoAttr{
                id:             :expediente_asociado,
                id_payload:     "contentref",
                type:           :string
            }

            @executed_by %Struct.InfoAttr{
                id:             :ejecutado_por,
                id_payload:     "executedby",
                type:           :string
            }

            @start_date %Struct.InfoAttr{
                id:             :fecha_inicio,
                id_payload:     "ini",
                type:           :timestamp
            }

            @end_date %Struct.InfoAttr{
                id:             :fecha_fin,
                id_payload:     "fin",
                type:           :timestamp
            }

            @name %Struct.InfoAttr{
                id:             :nombre,
                id_payload:     "name",
                type:           :string
            }

            @status %Struct.InfoAttr{
                id:             :estado,
                id_payload:     "status",
                type:           :string
            }

            @elapsed_working_time %Struct.InfoAttr{
                id:             :tiempo_laborable_transcurrido,
                type:           :integer,
                default_value:  -1
            }

            @timestamp %Struct.InfoAttr{
                id:             :timestamp,
                type:           :integer
            }

            ################
            ### Configuration
            ################

            task_config(
                app: :my_etl_app,
                table_name: "tasks",
                group_by_keys: [@contentref, @name],
                timestamp: @timestamp,
                value_type: "tarea",
                elapsed_time_config: %{
                    start_date_attr: @start_date,
                    end_date_attr: @end_date,
                    target_attr: @elapsed_working_time,
                    business: :my_business
                },
                slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],
                slack_env_var: System.get_env("ENVIRONMENT")
            )

            ################
            ### Attributes Lists
            ################

            own_attributes [
                @contentref,
                @executed_by,
                @start_date,
                @end_date,
                @name,
                @status
            ]

            computed_attributes [
                @elapsed_working_time,
                @timestamp
            ]

            ################
            ### Generate Helper Functions
            ################

            generate_task_helper_functions()

            ################
            ### Custom Implementation (Optional)
            ################

            # Override insert_by_lote if you need custom logic:
            # def insert_by_lote(batch, batch_id, pg_conn) do
            #     # Custom implementation using helper functions
            # end

            # Override after_insert for post-processing:
            # def after_insert(batch, batch_id, pg_conn) do
            #     # e.g., Entity.Task.ComplexSLA.search_and_insert_several(batch, batch_id, pg_conn)
            # end
        end

    ## Available Macros

    - `task_config/1` - Configure the task entity
    - `own_attributes/1` - Define the list of own attributes (from payload)
    - `computed_attributes/1` - Define computed/derived attributes
    - `generate_task_helper_functions/0` - Generate all helper functions

    ## Generated Functions

    After calling `generate_task_helper_functions/0`, the following functions are available:

    ### Required Functions
    - `attr_list/0` - Returns complete list of attributes
    - `table_name/0` - Returns PostgreSQL table name

    ### Configuration Functions
    - `application_name/0` - Returns the configured app name
    - `group_by_keys/0` - Returns the keys used for grouping
    - `timestamp_attr/0` - Returns the timestamp attribute
    - `elapsed_time_config/0` - Returns elapsed time configuration
    - `value_type/0` - Returns the type value for the record

    ### Helper Functions (Building Blocks)
    - `group_by_composite_key/1` - Groups payloads by composite key
    - `build_data/1` - Builds task data from payloads
    - `calculate_elapsed_time/1` - Calculates elapsed working time
    - `prepare_record/3` - Prepares a single record for PostgreSQL
    - `execute_insert/3` - Executes insert in PostgreSQL
    - `execute_insert_with_retry/3` - Executes with retry strategy
    - `after_insert/3` - Hook for post-insert processing
    - `handle_processing_error/4` - Handles errors
    - `parse_composite_key/1` - Parses composite key into components

    ### Main Function
    - `insert_by_lote/3` - Default implementation (overridable)

    ## Getter Functions

    Getter functions are automatically generated for each attribute defined in
    `own_attributes/1` and `computed_attributes/1`.
    """

    @doc """
    Callback invoked when `use DataModel.TaskPg.Base` is called.

    Imports the necessary macros and sets up the module.
    """
    defmacro __using__(_opts) do
        quote do
            alias Struct.InfoAttr
            alias Common.Payload
            alias Database.Postgres
            alias Notification.Notify
            alias Timex

            import DataModel.TaskPg.Macro

            @before_compile unquote(__MODULE__)
        end
    end

    @doc """
    Callback invoked before the module is compiled.
    Validates that required configurations have been defined.
    """
    defmacro __before_compile__(_env) do
        quote do
            unless Module.has_attribute?(__MODULE__, :task_config) do
                raise "DataModel.TaskPg.Base requires task_config/1 to be called"
            end
        end
    end


end
