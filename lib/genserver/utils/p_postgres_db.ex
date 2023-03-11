
defprotocol Genserver.Utils.PPostgresDb do
    @moduledoc"""
    Protocol oriented to load data from a table in a database in postgres
    """

    @doc"""
    Extracts the new rows from a certain table and inserts them into Bigquery

    ### Parameter:

        - business: Atom. Business to which the data points.

    """
    @spec load(atom) :: any
    def load(business)

end
