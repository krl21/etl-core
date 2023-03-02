
defmodule Connection.Ticket do
    @moduledoc"""
    Module for working with access tickets
    """

    import Connection.Http, only: [get: 2]

    @doc"""
    Returns a valid ticket, depending on the user. By default, the generic user is considered.

    ### Parameters:

        - url: String. Url to consult. It is assumed that the url contains 2 parameters to replace them: <username>, <password>.

        - headers: List.

        - username: String. Username.

        - password: String. Password.

    ### Return:

        - {Atom, String} | Exception . The atom can take the values: ok or error. The string will be the ticket or the error message.

    """
    def get(url, headers, username, password)
        when is_binary(url) and is_list(headers) and
            is_binary(username) and is_binary(password) do
            url
            |> String.replace("<username>", username)
            |> String.replace("<password>", password)
            |> get(headers)
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
