
defmodule Connection.Ticket do
    @moduledoc"""
    Module for working with access tickets
    """

    alias Connection.Http

    @doc"""
    Returns a valid ticket, depending on the user. By default, the generic user is considered.

    ### Parameters:

        - url: String. Url to consult.

        - headers: List.

        - username: String. Username.

        - password: String. Password.

    ### Return:

        - {Atom, String} | Exception . The atom can take the values: ok or error. The string will be the ticket or the error message.

    """
    def get(url, headers)
        when is_binary(url) and is_list(headers) do
            url
            |> Http.get(headers)
            |> case do
                {:error, error} ->
                    {:error, error}

                {:ok, %HTTPoison.Response{body: body}} ->
                    ticket =
                        body
                        |> Poison.decode!()
                        |> Map.get("ticket")
                    {:ok, ticket}
            end
    end


end
