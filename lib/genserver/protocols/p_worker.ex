
defprotocol Genserver.Protocols.PWorker do
    @moduledoc"""
    Protocol oriented to the definition of the function that the message lot will take, processed it if necessary and sent it to the corresponding module, for processing
    """

    @doc"""
    Sends to process the batch of messages, according to the business from which it comes

    ### Parameters:

        - batch: List of map. Payloads.

        - batch_id: String. Batch identifier.

        - conn_odbc_pid: Process. Process connecting Elixir and ODBC.

        - business: Atom. Business type.

    """
    def perform(batch, batch_id, pid, business)


end
