
defmodule DataModel.Task.Base do
    @moduledoc """
    Macros and utilities for defining Task entities.

    ## Usage example:

        defmodule Entity.Task.Task do
            use DataModel.Task.Base

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
                table_key: :task,
                group_by_keys: [@contentref, @name],
                timestamp: @timestamp,
                elapsed_time_config: %{
                    start_date_attr: @start_date,
                    end_date_attr: @end_date,
                    target_attr: @elapsed_working_time,
                    business: :my_business
                }
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
            # def insert_by_lote(batch, batch_id) do
            #     # Custom implementation using helper functions
            # end

            # Override after_insert for post-processing:
            # def after_insert(batch, batch_id) do
            #     # e.g., Entity.Task.ComplexSLA.search_and_insert_several(batch, batch_id)
            # end

            # Override handle_processing_error for custom error handling:
            # def handle_processing_error(batch_id, composite_key, error, context) do
            #     # Custom error handling with Slack notifications, etc.
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
    - `table_id/0` - Returns table identifier from config

    ### Configuration Functions
    - `application_name/0` - Returns the configured app name
    - `group_by_keys/0` - Returns the keys used for grouping
    - `timestamp_attr/0` - Returns the timestamp attribute
    - `elapsed_time_config/0` - Returns elapsed time configuration

    ### Helper Functions (Building Blocks)
    - `group_by_composite_key/1` - Groups payloads by composite key
    - `build_data/1` - Builds task data from payloads
    - `calculate_elapsed_time/1` - Calculates elapsed working time
    - `prepare_insert_query/3` - Prepares a single insert query
    - `build_insert_tuples/1` - Builds insertion tuples
    - `execute_insert/2` - Executes insert in database
    - `after_insert/2` - Hook for post-insert processing
    - `handle_processing_error/4` - Handles errors
    - `parse_composite_key/1` - Parses composite key into components

    ### Main Function
    - `insert_by_lote/2` - Default implementation (overridable)

    ## Getter Functions

    Getter functions are automatically generated for each attribute defined in
    `own_attributes/1` and `computed_attributes/1`. For example, if you define
    `@contentref`, a function `contentref/0` will be generated.
    """

    @doc """
    Callback invoked when `use DataModel.Task.Base` is called.

    Imports the necessary macros and sets up the module.
    """
    defmacro __using__(_opts) do
        quote do
            import DataModel.Task.Macro
        end
    end


end
