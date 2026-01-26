
defmodule Type.Normalize do
    @moduledoc """
    Module for character normalization and encoding conversion.
    """

    #
    # Character mappings are loaded from external JSON file at compile time
    #
    @external_resource Path.join(__DIR__, "char_mappings.json")
    @char_mappings (
        Path.join(__DIR__, "char_mappings.json")
        |> File.read!()
        |> Jason.decode!()
    )

    @spanish_chars @char_mappings["spanish_chars"]
    @unicode_chars @char_mappings["unicode_chars"]
    @denormalize_chars @char_mappings["denormalize"]

    @doc """
    Normalizes special characters including Spanish accents and common special characters.

    ### Parameters:
        - str: String to normalize

    ### Return:
        - String with normalized special characters

    ### Examples:
        iex> Type.Normalize.normalize_special_chars("José María")
        "Jos%ee% Mar%ii%a"

        iex> Type.Normalize.normalize_special_chars("niño")
        "ni%nn%o"
    """
    def normalize_special_chars(str) do
        str
        |> normalize_spanish_chars()
        |> normalize_unicode_chars()
        |> whitelist_ascii_chars()
    end

    #
    # Normalizes Spanish special characters, whitespace, and apostrophes.
    #
    # ### Parameters:
    #     - str: String to normalize
    #
    # ### Return:
    #     - String with Spanish characters encoded and whitespace normalized
    #
    defp normalize_spanish_chars(nil), do: nil

    defp normalize_spanish_chars(str) do
        Enum.reduce(@spanish_chars, str, fn {from, to}, acc ->
            String.replace(acc, from, to)
        end)
    end

    #
    # Normalizes Unicode characters to their ASCII equivalents.
    #
    # ### Parameters:
    #     - str: String to normalize (can be nil)
    #
    # ### Return:
    #     - String with normalized Unicode characters, or nil if input is nil
    #
    defp normalize_unicode_chars(nil), do: nil

    defp normalize_unicode_chars(str) do
        Enum.reduce(@unicode_chars, str, fn {from, to}, acc ->
            String.replace(acc, from, to)
        end)
    end

    #
    # Removes characters that are not in the ASCII whitelist.
    #
    # This function removes any characters that are not:
    # - Letters (A-Z, a-z)
    # - Numbers (0-9)
    # - Whitespace
    # - Common punctuation: .,;:_-!¡¿?(){}[]%+/<>=~*
    # - Special tokens: EUR, GBP, YEN, KRW, RUB, VND, INR, NGN, inf, ok, 0/00
    #
    # ### Parameters:
    #     - str: String to filter
    #
    # ### Return:
    #     - String with only whitelisted ASCII characters remaining
    #
    defp whitelist_ascii_chars(nil), do: ""

    defp whitelist_ascii_chars(str) when is_binary(str) do
        try do
            str
            |> String.to_charlist()
            |> Enum.filter(fn char -> char >= 32 and char <= 126 end)
            |> List.to_string()
        rescue
            _ -> ""
        end
    end

    defp whitelist_ascii_chars(_), do: ""

    @doc """
    Reverses the normalization done by `normalize_special_chars/1`.

    ### Parameters:
        - str: String with encoded placeholders

    ### Return:
        - String with original characters restored

    ### Examples:
        iex> Type.Normalize.denormalize_special_chars("Jos%ee% Mar%ii%a")
        "José María"

        iex> Type.Normalize.denormalize_special_chars("ni%nn%o")
        "niño"
    """
    def denormalize_special_chars(str) do
        Enum.reduce(@denormalize_chars, str, fn {from, to}, acc ->
            String.replace(acc, from, to)
        end)
    end

    @doc """
    Normalizes a string for ASCII compatibility.

    ### Parameters:
        - str: String to normalize (can be nil)

    ### Return:
        - ASCII-compatible string, or nil if input is nil

    ### Examples:
        iex> Type.Normalize.to_ascii("José María—2023")
        "Jos%ee% Mar%ii%a-2023"

        iex> Type.Normalize.to_ascii(nil)
        nil
    """
    def to_ascii(nil), do: nil
    def to_ascii(str), do: normalize_special_chars(str)

end
