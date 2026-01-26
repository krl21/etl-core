
defprotocol Genserver.Protocols.PWorker do
    @moduledoc"""
    Protocol oriented to the definition of the function that the message lot will take, processed it if necessary and sent it to the corresponding module, for processing
    """

    @doc"""
    Sends to process the batch of messages, according to the business from which it comes

    ### Parameters:
        - batch: List of map. Payloads.
        - batch_id: String. Batch identifier.
        - business: Atom. Business type.
        - info: any. Additional context/resources (e.g., pg_conn, config). Can be nil if not needed.

    """
    def perform(batch, batch_id, business, info)


end
