
defmodule File.FileManager do
    @moduledoc"""
    Tools for working with files
    """

    @doc"""
    Load JSON into memory

    ### Parameter:

        - filename: String or String List indicating the path of files in JSON format to read

    ### Examples:

        eix> load_json("hello.json")
        {word: "world"}

        eix> load_json(["hello.txt", "foo.json"])
        [{word: "world"}, {key: "bar"}]

        eix> filename = "./file.txt" # fake file path
        eix> load_json(filename)
        {:error, :enoent}

        eix> filename = "./file.txt" # misdefined JSON file
        eix> load_json(filename)
        {:error, %Poison.Parse{...}}

    """
    def load_json(filename) when is_binary(filename) do
        load_jsonp(filename)
    end

    def load_json(filename) when is_list(filename) do
        Enum.map(filename, fn path -> load_json(path) end)
    end

    defp load_jsonp(filename) do
        with {:ok, body} <- File.read(filename),
             {:ok, json} <- Poison.decode(body)
            do
                {:ok, json}
        else
            error -> error
        end
    end

    @doc"""
    Stores the data in a JSON file, a format supported for batch loading in BigQuery. The file name matches the time it was issued in UNIX format.

    Parameters:

        - data: List of map. Data.

        - path: String. Local path to store the file.

    ### Return:

        - :ok | Exception

    """
    def to_json_for_bigquery(data, path \\ ".")
        when is_list(data) and is_binary(path) do
        lines =
            data
            |> Enum.map(fn a -> Poison.encode!(a) end)
            |> Enum.reduce("", fn a, acc -> if acc == "" do a else acc <> "\n" <> a end end)

        name =
            Timex.now()
            |> Timex.to_unix()
            |> Integer.to_string()
            |> Kernel.<>(".json")
        path = Path.join(path, name)

        File.write(path, lines)
    end

    @doc"""
    Store in file, a text

    ### Parameters:

        - text: String: Text to put in the document.

        - path: String. File path.

    """
    def save(text, path)
        when is_binary(text) and is_binary(path) do
            File.write(path, text)
    end

    @doc"""
    Returns text stored in a file

    ### Parameters:

        - path: String. File path.

    ### Return:

        - String

    """
    def load(path)
        when is_binary(path) do
            {:ok, text} = File.read(path)
            text
    end



end
