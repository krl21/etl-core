defmodule Statement.ElasticTest do
    use ExUnit.Case, async: true

    alias Statement.Elastic

    describe "build_query/1" do
        test "builds a match_all query with the given size, as valid JSON" do
            result = Elastic.build_query(50)
            decoded = Poison.decode!(result)

            assert decoded["query"] == %{"match_all" => %{}}
            assert decoded["size"] == 50
        end
    end

    describe "build_query/6" do
        test "defaults from to 0 and size to 100" do
            result = Elastic.build_query("campo", "rango", "2024-01-01", "2024-12-31")
            decoded = Poison.decode!(result)

            assert decoded["from"] == 0
            assert decoded["size"] == 100
            assert decoded["_source"] == ["campo"]

            range = get_in(decoded, ["query", "bool", "must", Access.at(0), "range", "rango"])
            assert range == %{"gte" => "2024-01-01", "lte" => "2024-12-31"}
        end

        test "accepts explicit from/size" do
            result = Elastic.build_query("campo", "rango", "a", "b", 10, 5)
            decoded = Poison.decode!(result)

            assert decoded["from"] == 10
            assert decoded["size"] == 5
        end

        test "excludes deleted=true documents via a must_not clause" do
            result = Elastic.build_query("campo", "rango", "a", "b")
            decoded = Poison.decode!(result)

            must_not = get_in(decoded, ["query", "bool", "must", Access.at(1), "bool", "must_not", Access.at(0), "term"])
            assert must_not == %{"deleted" => true}
        end
    end

    describe "build_query_inside/3" do
        test "builds the same range/must_not shape, without the outer envelope" do
            result = Elastic.build_query_inside("rango", "a", "b")
            decoded = Poison.decode!(result)

            assert get_in(decoded, ["bool", "must", Access.at(0), "range", "rango"]) == %{"gte" => "a", "lte" => "b"}
            assert get_in(decoded, ["bool", "must", Access.at(1), "bool", "must_not", Access.at(0), "term"]) == %{"deleted" => true}
        end
    end
end
