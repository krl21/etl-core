
defprotocol Type.PDocumentaryTypeOf do
    @moduledoc"""
    Module for the work of documentaries in NodeService

    """

    @doc"""
    Returns the type of documentary, given the business

    ### Parameter:

        - business: String. Business.

    ### Return:

        - String

    """
    def documentary_type_of(business)

end
