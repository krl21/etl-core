
defprotocol Genserver.Utils.PForcedLoad do
    @moduledoc"""
    Definition of the function for forced or manual data loading
    """

    @doc"""
    Load the data

    ### Parameter:

    - business: Atom. Business to which the data points.

    """
    @spec run(pid) :: any
    def run(business)



end
