defmodule File.FileManagerTest do
    use ExUnit.Case, async: true

    alias File.FileManager

    setup do
        dir = Path.join(System.tmp_dir!(), "etl_core_file_manager_test_#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)
        on_exit(fn -> File.rm_rf!(dir) end)
        %{dir: dir}
    end

    describe "load_json/1" do
        test "reads and decodes a single JSON file", %{dir: dir} do
            path = Path.join(dir, "a.json")
            File.write!(path, Poison.encode!(%{"word" => "world"}))

            assert FileManager.load_json(path) == {:ok, %{"word" => "world"}}
        end

        test "reads a list of files, one result per path", %{dir: dir} do
            path1 = Path.join(dir, "a.json")
            path2 = Path.join(dir, "b.json")
            File.write!(path1, Poison.encode!(%{"a" => 1}))
            File.write!(path2, Poison.encode!(%{"b" => 2}))

            assert FileManager.load_json([path1, path2]) == [{:ok, %{"a" => 1}}, {:ok, %{"b" => 2}}]
        end

        test "a missing file returns {:error, :enoent}" do
            assert {:error, :enoent} = FileManager.load_json("/nonexistent/path/x.json")
        end

        test "malformed JSON returns a Poison parse error" do
            path = Path.join(System.tmp_dir!(), "etl_core_bad_#{System.unique_integer([:positive])}.json")
            File.write!(path, "{not valid json")
            on_exit(fn -> File.rm(path) end)

            assert {:error, _reason} = FileManager.load_json(path)
        end
    end

    describe "to_json_for_bigquery/2" do
        test "writes one JSON line per record, timestamped by the current unix time", %{dir: dir} do
            assert :ok = FileManager.to_json_for_bigquery([%{a: 1}, %{b: 2}], dir)

            [written] = File.ls!(dir)
            assert written =~ ~r/^\d+\.json$/

            content = File.read!(Path.join(dir, written))
            assert content == "#{Poison.encode!(%{a: 1})}\n#{Poison.encode!(%{b: 2})}"
        end

        test "an empty list writes an empty file", %{dir: dir} do
            assert :ok = FileManager.to_json_for_bigquery([], dir)
            [written] = File.ls!(dir)
            assert File.read!(Path.join(dir, written)) == ""
        end
    end

    describe "save/2 and load/1" do
        test "round-trip a piece of text through disk", %{dir: dir} do
            path = Path.join(dir, "note.txt")
            assert :ok = FileManager.save("hello", path)
            assert FileManager.load(path) == {:ok, "hello"}
        end
    end
end
