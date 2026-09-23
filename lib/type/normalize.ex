defmodule Type.Normalize do
    @moduledoc """
    Module for character normalization and encoding conversion.
    """

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
        str
        |> String.replace("\n", " ")
        |> String.replace("\t", "")
        |> String.replace("'", "%r_%")
        |> String.replace("ñ", "%nn%")
        |> String.replace("Ñ", "%nN%")
        |> String.replace("á", "%aa%")
        |> String.replace("Á", "%aA%")
        |> String.replace("é", "%ee%")
        |> String.replace("É", "%eE%")
        |> String.replace("í", "%ii%")
        |> String.replace("Í", "%iI%")
        |> String.replace("ó", "%oo%")
        |> String.replace("Ó", "%oO%")
        |> String.replace("ú", "%uu%")
        |> String.replace("Ú", "%uU%")
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
        str
        |> String.replace("'", "%r_%") # '
        |> String.replace("\u{2018}", "%r_%") # ' (Left single quotation mark)
        |> String.replace("\u{2019}", "%r_%") # ' (Right single quotation mark)
        |> String.replace("\u{2032}", "%r_%") # ′ (Prime)
        |> String.replace("\u{2039}", "%r_%") # ‹ (Single left-pointing angle quotation mark)
        |> String.replace("\u{203A}", "%r_%") # › (Single right-pointing angle quotation mark)
        |> String.replace("\u{201C}", "\"") # " (Left double quotation mark)
        |> String.replace("\u{201D}", "\"") # " (Right double quotation mark)
        |> String.replace("\u{2033}", "\"") # ″ (Double prime)
        |> String.replace("\u{00AB}", "\"") # « (Left-pointing double angle quotation mark)
        |> String.replace("\u{00BB}", "\"") # » (Right-pointing double angle quotation mark)
        |> String.replace("\u{2010}", "-") # ‐ (Hyphen)
        |> String.replace("\u{2011}", "-") # ‑ (Non-breaking hyphen)
        |> String.replace("\u{2012}", "-") # ‒ (Figure dash)
        |> String.replace("\u{2013}", "-") # – (En dash)
        |> String.replace("\u{2014}", "-") # — (Em dash)
        |> String.replace("\u{2015}", "-") # ― (Horizontal bar)
        |> String.replace("\u{00A0}", " ") #   (Non-breaking space)
        |> String.replace("\u{2000}", " ") #   (En quad)
        |> String.replace("\u{2001}", " ") #   (Em quad)
        |> String.replace("\u{2002}", " ") #   (En space)
        |> String.replace("\u{2003}", " ") #   (Em space)
        |> String.replace("\u{2004}", " ") #   (Three-per-em space)
        |> String.replace("\u{2005}", " ") #   (Four-per-em space)
        |> String.replace("\u{2006}", " ") #   (Six-per-em space)
        |> String.replace("\u{2007}", " ") #   (Figure space)
        |> String.replace("\u{2008}", " ") #   (Punctuation space)
        |> String.replace("\u{2009}", " ") #   (Thin space)
        |> String.replace("\u{202F}", " ") #   (Narrow no-break space)
        |> String.replace("\u{205F}", " ") #   (Medium mathematical space)
        |> String.replace("\u{200A}", " ") #   (Hair space)
        |> String.replace("\u{00AD}", "") # ­ (Soft hyphen)
        |> String.replace("\u{200B}", "") # ​ (Zero width space)
        |> String.replace("\u{2060}", "") # ⁠ (Word joiner)
        |> String.replace("\u{FEFF}", "") # ﻿ (Zero width no-break space)
        |> String.replace("\u{2022}", ".") # • (Bullet)
        |> String.replace("\u{00B7}", ".") # · (Middle dot)
        |> String.replace("\u{2219}", ".") # ∙ (bullet operator)
        |> String.replace("\u{22C5}", ".") # ⋅ (dot operator)
        |> String.replace("\u{00E4}", "a") # ä
        |> String.replace("\u{00E2}", "a") # â
        |> String.replace("\u{00E3}", "a") # ã
        |> String.replace("\u{00E5}", "a") # å
        |> String.replace("\u{0101}", "a") # ā
        |> String.replace("\u{0103}", "a") # ă
        |> String.replace("\u{0105}", "a") # ą
        |> String.replace("\u{00AA}", "a") # ª (feminine ordinal indicator)
        |> String.replace("\u{0430}", "a") # а (Cyrillic)
        |> String.replace("\u{00C2}", "A") # Â
        |> String.replace("\u{00C4}", "A") # Ä
        |> String.replace("\u{00C3}", "A") # Ã
        |> String.replace("\u{00C5}", "A") # Å
        |> String.replace("\u{0100}", "A") # Ā
        |> String.replace("\u{0102}", "A") # Ă
        |> String.replace("\u{0104}", "A") # Ą
        |> String.replace("\u{0410}", "A") # А (Cyrillic)
        |> String.replace("\u{0391}", "A") # Α (Greek alpha)
        |> String.replace("\u{00EB}", "e") # ë
        |> String.replace("\u{00EA}", "e") # ê
        |> String.replace("\u{0113}", "e") # ē
        |> String.replace("\u{0115}", "e") # ĕ
        |> String.replace("\u{0117}", "e") # ė
        |> String.replace("\u{0119}", "e") # ę
        |> String.replace("\u{011B}", "e") # ě
        |> String.replace("\u{0435}", "e") # е (Cyrillic)
        |> String.replace("\u{0451}", "e") # ё (Cyrillic)
        |> String.replace("\u{00CA}", "E") # Ê
        |> String.replace("\u{00CB}", "E") # Ë
        |> String.replace("\u{0112}", "E") # Ē
        |> String.replace("\u{0114}", "E") # Ĕ
        |> String.replace("\u{0116}", "E") # Ė
        |> String.replace("\u{0118}", "E") # Ę
        |> String.replace("\u{011A}", "E") # Ě
        |> String.replace("\u{0415}", "E") # Е (Cyrillic)
        |> String.replace("\u{0395}", "E") # Ε (Greek epsilon)
        |> String.replace("\u{00EF}", "i") # ï
        |> String.replace("\u{00EE}", "i") # î
        |> String.replace("\u{0129}", "i") # ĩ
        |> String.replace("\u{012B}", "i") # ī
        |> String.replace("\u{012D}", "i") # ĭ
        |> String.replace("\u{012F}", "i") # į
        |> String.replace("\u{0131}", "i") # ı
        |> String.replace("\u{00CF}", "I") # Ï
        |> String.replace("\u{00CE}", "I") # Î
        |> String.replace("\u{0128}", "I") # Ĩ
        |> String.replace("\u{012A}", "I") # Ī
        |> String.replace("\u{012C}", "I") # Ĭ
        |> String.replace("\u{012E}", "I") # Į
        |> String.replace("\u{0130}", "I") # İ
        |> String.replace("\u{00F6}", "o") # ö
        |> String.replace("\u{00F4}", "o") # ô
        |> String.replace("\u{00F5}", "o") # õ
        |> String.replace("\u{014D}", "o") # ō
        |> String.replace("\u{014F}", "o") # ŏ
        |> String.replace("\u{0151}", "o") # ő
        |> String.replace("\u{00F8}", "o") # ø
        |> String.replace("\u{00B0}", "o") # ° (degree sign)
        |> String.replace("\u{00BA}", "o") # º (masculine ordinal indicator)
        |> String.replace("\u{043E}", "o") # о (Cyrillic)
        |> String.replace("\u{03BF}", "o") # ο (Greek omicron)
        |> String.replace("\u{00D6}", "O") # Ö
        |> String.replace("\u{00D4}", "O") # Ô
        |> String.replace("\u{00D5}", "O") # Õ
        |> String.replace("\u{014C}", "O") # Ō
        |> String.replace("\u{014E}", "O") # Ŏ
        |> String.replace("\u{0150}", "O") # Ő
        |> String.replace("\u{00D8}", "O") # Ø
        |> String.replace("\u{041E}", "O") # О (Cyrillic)
        |> String.replace("\u{039F}", "O") # Ο (Greek omicron)
        |> String.replace("\u{00FC}", "u") # ü
        |> String.replace("\u{00FB}", "u") # û
        |> String.replace("\u{0169}", "u") # ũ
        |> String.replace("\u{016B}", "u") # ū
        |> String.replace("\u{016D}", "u") # ŭ
        |> String.replace("\u{016F}", "u") # ů
        |> String.replace("\u{0171}", "u") # ű
        |> String.replace("\u{0173}", "u") # ų
        |> String.replace("\u{00B5}", "u") # µ (Micro sign)
        |> String.replace("\u{00DC}", "U") # Ü
        |> String.replace("\u{00DB}", "U") # Û
        |> String.replace("\u{0168}", "U") # Ũ
        |> String.replace("\u{016A}", "U") # Ū
        |> String.replace("\u{016C}", "U") # Ŭ
        |> String.replace("\u{016E}", "U") # Ů
        |> String.replace("\u{0170}", "U") # Ű
        |> String.replace("\u{0172}", "U") # Ų
        |> String.replace("\u{00E7}", "c") # ç
        |> String.replace("\u{0107}", "c") # ć
        |> String.replace("\u{010D}", "c") # č
        |> String.replace("\u{0109}", "c") # ĉ
        |> String.replace("\u{010B}", "c") # ċ
        |> String.replace("\u{00A2}", "c") # ¢ (cent sign)
        |> String.replace("\u{0441}", "c") # с (Cyrillic)
        |> String.replace("\u{00C7}", "C") # Ç
        |> String.replace("\u{0106}", "C") # Ć
        |> String.replace("\u{010C}", "C") # Č
        |> String.replace("\u{0108}", "C") # Ĉ
        |> String.replace("\u{010A}", "C") # Ċ
        |> String.replace("\u{0421}", "C") # С (Cyrillic)
        |> String.replace("\u{00F0}", "d") # ð
        |> String.replace("\u{00D0}", "D") # Ð
        |> String.replace("\u{0142}", "l") # ł
        |> String.replace("\u{0141}", "L") # Ł
        |> String.replace("\u{0159}", "r") # ř
        |> String.replace("\u{0155}", "r") # ŕ
        |> String.replace("\u{0157}", "r") # ŗ
        |> String.replace("\u{0158}", "R") # Ř
        |> String.replace("\u{0154}", "R") # Ŕ
        |> String.replace("\u{0156}", "R") # Ŗ
        |> String.replace("\u{015B}", "s") # ś
        |> String.replace("\u{0161}", "s") # š
        |> String.replace("\u{015D}", "s") # ŝ
        |> String.replace("\u{0219}", "s") # ș
        |> String.replace("\u{015F}", "s") # ş
        |> String.replace("\u{015A}", "S") # Ś
        |> String.replace("\u{0160}", "S") # Š
        |> String.replace("\u{015C}", "S") # Ŝ
        |> String.replace("\u{0218}", "S") # Ș
        |> String.replace("\u{015E}", "S") # Ş
        |> String.replace("\u{00A7}", "S") # § (Section sign)
        |> String.replace("\u{0165}", "t") # ť
        |> String.replace("\u{021B}", "t") # ț
        |> String.replace("\u{0163}", "t") # ţ
        |> String.replace("\u{0164}", "T") # Ť
        |> String.replace("\u{0162}", "T") # Ţ
        |> String.replace("\u{0422}", "T") # Т (Cyrillic)
        |> String.replace("\u{017A}", "z") # ź
        |> String.replace("\u{017E}", "z") # ž
        |> String.replace("\u{017C}", "z") # ż
        |> String.replace("\u{0179}", "Z") # Ź
        |> String.replace("\u{017D}", "Z") # Ž
        |> String.replace("\u{017B}", "Z") # Ż
        |> String.replace("\u{011F}", "g") # ğ
        |> String.replace("\u{011D}", "g") # ĝ
        |> String.replace("\u{0121}", "g") # ġ
        |> String.replace("\u{0123}", "g") # ģ
        |> String.replace("\u{011E}", "G") # Ğ
        |> String.replace("\u{011C}", "G") # Ĝ
        |> String.replace("\u{0120}", "G") # Ġ
        |> String.replace("\u{0122}", "G") # Ģ
        |> String.replace("\u{00FD}", "y") # ý
        |> String.replace("\u{00FF}", "y") # ÿ
        |> String.replace("\u{0177}", "y") # ŷ
        |> String.replace("\u{00DD}", "Y") # Ý
        |> String.replace("\u{0178}", "Y") # Ÿ
        |> String.replace("\u{0176}", "Y") # Ŷ
        |> String.replace("\u{00D7}", "x") # × (Multiplication sign)
        |> String.replace("\u{0445}", "x") # х (Cyrillic)
        |> String.replace("\u{2717}", "x") # ✗ (ballot x)
        |> String.replace("\u{2718}", "x") # ✘ (heavy ballot x)
        |> String.replace("\u{0425}", "X") # Х (Cyrillic)
        |> String.replace("\u{0412}", "B") # В (Cyrillic)
        |> String.replace("\u{041D}", "H") # Н (Cyrillic)
        |> String.replace("\u{041A}", "K") # К (Cyrillic)
        |> String.replace("\u{041C}", "M") # М (Cyrillic)
        |> String.replace("\u{0440}", "p") # р (Cyrillic)
        |> String.replace("\u{00B6}", "P") # ¶ (Pilcrow sign)
        |> String.replace("\u{0420}", "P") # Р (Cyrillic)
        |> String.replace("\u{00DF}", "ss") # ß
        |> String.replace("\u{1E9E}", "SS") # ẞ
        |> String.replace("\u{00FE}", "th") # þ
        |> String.replace("\u{00DE}", "Th") # Þ
        |> String.replace("\u{00C6}", "AE") # Æ
        |> String.replace("\u{00E6}", "ae") # æ
        |> String.replace("\u{0152}", "OE") # Œ
        |> String.replace("\u{0153}", "oe") # œ
        |> String.replace("\u{2026}", "...") # … (Horizontal ellipsis)
        |> String.replace("\u{20AC}", "EUR") # € (Euro sign)
        |> String.replace("\u{00A3}", "GBP") # £ (Pound sign)
        |> String.replace("\u{00A5}", "YEN") # ¥ (Yen sign)
        |> String.replace("\u{00A9}", "(c)") # © (Copyright sign)
        |> String.replace("\u{00AE}", "(R)") # ® (Registered sign)
        |> String.replace("\u{2122}", "(TM)") # ™ (Trade mark sign)
        |> String.replace("\u{00B1}", "+/-") # ± (Plus-minus sign)
        |> String.replace("\u{2020}", "+") # † (Dagger)
        |> String.replace("\u{2021}", "++") # ‡ (Double dagger)
        |> String.replace("\u{00F7}", "/") # ÷ (Division sign)
        |> String.replace("\u{2248}", "~") # ≈ (almost equal to)
        |> String.replace("\u{2260}", "!=") # ≠ (not equal to)
        |> String.replace("\u{2264}", "<=") # ≤ (less-than or equal to)
        |> String.replace("\u{2265}", ">=") # ≥ (greater-than or equal to)
        |> String.replace("\u{2192}", "->") # → (rightwards arrow)
        |> String.replace("\u{2190}", "<-") # ← (leftwards arrow)
        |> String.replace("\u{2194}", "<->") # ↔ (left right arrow)
        |> String.replace("\u{2191}", "^") # ↑ (upwards arrow)
        |> String.replace("\u{2193}", "v") # ↓ (downwards arrow)
        |> String.replace("\u{2605}", "*") # ★ (black star)
        |> String.replace("\u{2606}", "*") # ☆ (white star)
        |> String.replace("\u{2713}", "ok") # ✓ (check mark)
        |> String.replace("\u{2714}", "ok") # ✔ (heavy check mark)
        |> String.replace("\u{221E}", "inf") # ∞ (infinity)
        |> String.replace("\u{2030}", "0/00") # ‰ (per mille sign)
        |> String.replace("\u{20A9}", "KRW") # ₩ (won sign)
        |> String.replace("\u{20BD}", "RUB") # ₽ (ruble sign)
        |> String.replace("\u{20AB}", "VND") # ₫ (dong sign)
        |> String.replace("\u{20B9}", "INR") # ₹ (rupee sign)
        |> String.replace("\u{20A6}", "NGN") # ₦ (naira sign)
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
        str
        |> String.replace("%r_%", "'")
        |> String.replace("%nn%", "ñ")
        |> String.replace("%nN%", "Ñ")
        |> String.replace("%aa%", "á")
        |> String.replace("%aA%", "Á")
        |> String.replace("%ee%", "é")
        |> String.replace("%eE%", "É")
        |> String.replace("%ii%", "í")
        |> String.replace("%iI%", "Í")
        |> String.replace("%oo%", "ó")
        |> String.replace("%oO%", "Ó")
        |> String.replace("%uu%", "ú")
        |> String.replace("%uU%", "Ú")
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
