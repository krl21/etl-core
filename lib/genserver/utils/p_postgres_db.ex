
defprotocol Genserver.Utils.PPostgresDb do
    @moduledoc"""
    Protocol oriented to load data from a table in a database in postgres
    """

    @doc"""
    Extracts the new rows from a certain table and inserts them into Bigquery

    ### Parameter:

        - business: Atom. Business to which the data points.

        - params: List. Other parameters of interest, if needed.

    """
    @spec load(atom, list) :: any
    def load(business, params)

end
