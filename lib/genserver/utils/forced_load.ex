
defprotocol Genserver.Utils.ForcedLoad do
    @moduledoc"""
    Definition of the function for forced or manual data loading
    """

    @doc"""
    Load the data

    ### Parameter:

        - business: Atom. Business to which the data points.

    """
    def load(business)



end
