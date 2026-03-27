
defprotocol Genserver.Protocols.PBigqueryPostProcess do
    @moduledoc """
    Protocol for executing post-processing logic after records are uploaded to BigQuery.
    """

    @fallback_to_any true

    @doc """
    Executes post-processing logic after BigQuery upload completes.

    ### Parameters:
        - business: Atom. Business type identifier.
        - type_: String. Type field value used to differentiate processing logic.
        - context: Map. Context information containing:
            - :uploaded_count (integer) - Number of records successfully uploaded
            - :successful_ids (list) - List of IDs that were successfully uploaded
            - :failed_ids (list) - List of IDs that failed to upload
            - :batch_id (string) - Batch identifier
            - :bq_table (string) - BigQuery table name
            - :bq_conn (pid) - BigQuery connection
            - :pg_table (string) - PostgreSQL table name
            - :pg_conn (pid) - PostgreSQL connection

    ### Returns:
        - :ok | {:ok, result} | {:error, reason}
    """
    @spec after_upload(atom, String.t(), map) :: :ok | {:ok, any} | {:error, any}
    def after_upload(business, type_, context)
end


defimpl Genserver.Protocols.PBigqueryPostProcess, for: Any do
    @moduledoc """
    Default implementation that does nothing.
    Used when no specific implementation exists for a business type.
    """
    def after_upload(_business, type_, _context), do: :ok
end
