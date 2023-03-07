
defmodule Connection.Ticket do
    @moduledoc"""
    Module for working with access tickets
    """

    import Connection.Http, only: [get: 2]
    import File.FileManager, only: [load: 1, save: 2]

    @doc"""
    Returns a valid ticket, depending on the user.

    ### Parameters:

        - url: String. Url to consult. It is assumed that the url contains 2 parameters to replace them: <username>, <password>.

        - headers: List.

        - username: String. Username.

        - password: String. Password.

        - folder: String. Folder path to store the ticket.

    ### Return:

        - {Atom, String} | Exception . The atom can take the values: ok or error. The string will be the ticket or the error message.

    """
    def get(url, headers, username, password, folder \\ "./tmp")
        when is_binary(url) and is_list(headers) and
            is_binary(username) and is_binary(password) do
            # url
            # |> String.replace("<username>", username)
            # |> String.replace("<password>", password)
            # |> get(headers)
            # |> case do
            #     {:error, error} ->
            #         {:error, error}

            #     {:ok, %HTTPoison.Response{body: body}} ->
            #         ticket =
            #             body
            #             |> Poison.decode!()
            #             |> Map.get("ticket")
            #         {:ok, ticket}
            # end
            Path.join(folder, :erlang.phash2(username <> password) |> to_string())
            |> load()
    end

    @doc"""
    Store a valid ticket, depending on the user. By default, the generic user is considered.

    ### Parameters:

        - url: String. Url to consult. It is assumed that the url contains 2 parameters to replace them: <username>, <password>.

        - headers: List.

        - username: String. Username.

        - password: String. Password.

        - folder: String. Folder path to store the ticket.

    ### Return:

        - {:ok, ticket (String)} | {:error, error_msg (String)}

    """
    def refresh(url, headers, username, password, folder \\ "./tmp")
        when is_binary(url) and is_list(headers) and
            is_binary(username) and is_binary(password) and
            is_binary(folder) do
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


                File.mkdir_p(folder)
                folder = Path.join(folder, :erlang.phash2(username <> password) |> to_string())
                save(ticket, folder)
        end
    end

end
