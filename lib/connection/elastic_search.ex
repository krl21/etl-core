
defmodule Connection.ElasticSearch do
    @moduledoc"""
    Module oriented to the creation of queries to ElasticSearch
    """

    alias Connection.Http
    alias Connection.Ticket
    alias Statement.Elastic

    #todo: obtener los detalles usando llamados a los genservers de node_service


    @doc"""
    Returns the ElasticSearch keyword to indicate how it will be used. It will only be consulted.

    ### Return:

        - String. ElasticSearch reserved word.

    """
    def mode() do
      "_search"
    end

    @doc"""
    Returns the indexed indices for `path`

    ### Parameters:

        - url: String. URL of the service. It is assumed that the url contains 2 parameters to replace them: "<type_documentary>", <mode>.

        - headers: List of tuple.

        - type_documentary: String. Documentary type.

        - mode: String. ElasticSearch access mode. Default value `_search`.

    ### Return:

        - List of Atom | Exception

    """
    def get_indexed_indices(url, headers, type_documentary, mode \\ "_search")
    when is_binary(url) and is_list(headers) and
        is_binary(type_documentary) and is_binary(mode) do

        url =
            url
            |> String.replace("<type_documentary>", type_documentary)
            |> String.replace("<mode>", mode)

        body = Elastic.build_query(1)

        Http.post(
            body,
            url,
            headers
        )
        |> case do
            {:error, _} = error ->
                error

            {:ok, %HTTPoison.Response{body: body}} ->
                body
                |> Poison.decode()
                |> case do
                    {:error, _} = error ->
                        error

                    {:ok, body} ->
                        body
                        |> Map.get("hits")
                        |> Map.get("hits")
                        |> hd()
                        |> Map.get("_source")
                        |> Map.keys()
                end
        end
    end

    @doc"""
    Returns all defined indices, contained in a closed range

    ### Parameters:

        - url: String. URL of the service. It is assumed that the url contains 2 parameters to replace them: "<type_documentary>", <mode>.

        - headers: List of tuple.

        - type_documentary: String. Documentary type.

        - mode: String. ElasticSearch access mode. Default value: "_search".

        - init_date: String. Range start date is included. Expected format `YYYY-MM-DDThh:mm:ss.mZ`.

        - end_date: String. Range end date is included. Expected format `YYYY-MM-DDThh:mm:ss.mZ`.

        - index_for_range: String. Index that allows searching by range. It must be considered in the set of ElasticSearch indexes.

        - index_to_return: String. Index that will be returned for each document, according to what ElasticSearch returns.

    ### Returns:

        - Exception | List of the values of the `index_to_return` index, in each document.

    """
    def get_from_range(url, headers, type_documentary, mode, init_date, end_date, index_for_range, index_to_return)
        when is_binary(url) and is_list(headers) and
            is_binary(type_documentary) and is_binary(mode) and
            is_binary(init_date) and is_binary(end_date) and
            is_binary(index_for_range) and is_binary(index_to_return) do

            # #todo: validar el formato que es el esperado, de `init_date` y `end_date`
            # indexs = get_indexed_indices(type_documentary)
            # if index_for_range not in indexs do
            #     raise("El indice `#{index_for_range}` no está en los definidos para el tipo de documental `#{type_documentary}`.")
            # end
            # #todo: validar que init_date <= end_date

            # if index_to_return not in indexs do
            #     raise("El indice `#{index_to_return}` no está en los definidos para el tipo de documental `#{type_documentary}`.")
            # end

            url =
                url
                |> String.replace("<type_documentary>", type_documentary)
                |> String.replace("<mode>", mode)
            body = Elastic.build_query(index_to_return, index_for_range, init_date, end_date)

            Http.post(
                body,
                url,
                headers
            )
            |> case do
                {:error, _} = error ->
                    error

                {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
                    body
                    |> Poison.decode()
                    |> case do
                        {:error, _} = error ->
                            error

                        {:ok, body} when status_code != 200 ->
                            {:error, body}

                        {:ok, body} ->
                            count = body
                                    |> Map.get("hits")
                                    |> Map.get("total")
                            build_from_pagination(url, headers, index_to_return, index_for_range, init_date, end_date, count, 0, [])
                    end
            end
    end

    #
    # Get all the information, browsing the page
    #
    # ### Parameters:
    #
    #     same parameters as get_from_range/8.
    #
    #     - total: Integer. number of records not yet retrieved.
    #
    #     - from: Integer. Displacement in taking records.
    #
    #     - acc: List. Records retrieved.
    #
    # ### Return:
    #
    #     - List
    #
    defp build_from_pagination(_, _, _, _, _, _, total, _, acc)  when total <= 0 do
        {:ok, acc}
    end

    defp build_from_pagination(url, headers, index_to_return, index_for_range, init_date, end_date, total, from, acc) do
        size = 25
        body = Elastic.build_query(index_to_return, index_for_range, init_date, end_date, from, size)

        Http.post(
            body,
            url,
            headers
        )
        |> case do
            {:error, error} ->
                {:error, error}

            {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
                Poison.decode(body)
                |> case do
                    {:error, _} = error ->
                        error

                    {:ok, body} when status_code != 200 ->
                        {:error, body}

                    {:ok, body} ->
                        list = body
                                |> Map.get("hits")
                                |> Map.get("hits")
                                |> Enum.map(fn hit ->
                                    hit
                                    |> Map.get("_source")
                                    |> Map.get(index_to_return)
                                end)

                        build_from_pagination(
                            url,
                            headers,
                            index_to_return,
                            index_for_range,
                            init_date,
                            end_date,
                            total - size,
                            from + size,
                            acc ++ list
                        )
                end
        end
    end

    @doc"""
    Returns all defined indices, contained in a closed range. Use a New Vehicles service.

    ### Parameters:

        - url: String. URL of the service. It is assumed that the url contains 2 parameters to replace them: "<type_documentary>", <mode>.

        - headers: List of tuple.

        -index_for_range: String. Index to use to filter by range.

        - start_value: String. Lower bound for filtering.

        - end_value: String. Upper bound for filtering.

        - index_to_return: List of string. List of indexed terms to return.

    ### Return:

        - {:ok, list of string} | {:error, string (message)}

    """
    def get_from_nv(url, headers, index_for_range, start_date, end_date, index_to_return, {url_ticket, headers_ticket, username, password})
        when is_binary(url) and is_list(headers) and
            is_binary(index_for_range) and is_binary(start_date) and
            is_binary(end_date) and is_list(index_to_return) and
            is_binary(url_ticket) and is_list(headers_ticket) and
            is_binary(username) and is_binary(username) do

                Ticket.get(
                    url_ticket,
                    headers_ticket,
                    username,
                    password
                )
                |> case do
                    {:error, _} = error ->
                        error

                    {:ok, ticket} ->
                        body = Elastic.build_query_inside(index_for_range, start_date, end_date)

                        url
                        |> String.replace("<from>", "0")
                        |> String.replace("<size>", "1")
                        |> String.replace("<ticket>", ticket)
                        |> get_data_url(headers, body)
                        |> case do
                            {:error, _} = error ->
                                error

                            {:ok, %{"response" => %{"search" => %{"hits" => %{"total" => total}}}}} ->
                                get_from_nv(url, ticket, body, headers, index_to_return, 0, 10, total, [])

                            {:ok, unexpected_result} ->
                                {:error, "Unexpected result: #{inspect unexpected_result}"}
                        end
                end
    end

    #
    #
    #
    def get_from_nv(_, _, _, _, _, _, _, total, acc) when total <= 0 do
        {:ok, acc}
    end

    def get_from_nv(url, ticket, body, headers, index_to_return, from, size, total, acc) do
        url
        |> String.replace("<from>", Integer.to_string(from))
        |> String.replace("<size>", Integer.to_string(size))
        |> String.replace("<ticket>", ticket)
        |> get_data_url(headers, body)
        |> case do
            {:error, error} ->
                {:error, error}

            {:ok, %{"response" => %{"search" => %{"hits" => %{"hits" => hits}}}}} ->
                acc_temp =
                    hits
                    |> Enum.map(fn hit ->
                        hit = Map.get(hit, "_source")
                        index_to_return
                        |> Enum.reduce([], fn key, acc -> acc ++ [{key, Map.get(hit, key)}] end)
                    end)

                get_from_nv(url, ticket, body, headers, index_to_return, from + size, size, total - size, acc ++ acc_temp)
        end
    end

    #
    #
    #
    defp get_data_url(url, headers, body) do
        Http.post(
            body,
            url,
            headers
        )
        |> case do
            {:error, error} ->
                {:error, "Error. Url: #{url}. Body: #{body}. Error: #{inspect error}"}

            {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
                {
                    status_code,
                    Poison.decode(body)
                }
                |> case do
                    {200, {:ok, data}} ->
                        {:ok, data}

                    {_, {_, error}} ->
                        {:error, "Error. Url: #{url}. Body: #{body}. Error: #{inspect error}"}
                end
        end
    end






end
