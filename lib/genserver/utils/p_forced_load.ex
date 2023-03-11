
defprotocol Genserver.Utils.PForcedLoad do
    @moduledoc"""
    Definition of the function for forced or manual data loading
    """

    @doc"""
    Load the data

    ### Parameter:

        - business: Atom. Business to which the data points.

        - params: List. Other parameters of interest, if needed.

    """
    @spec run(atom, list) :: any
    def run(business, params)



end
