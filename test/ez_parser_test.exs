defmodule EzParserTest do
  use ExUnit.Case
  doctest EzParser

  test "parses an .ez file" do
    assert %CodeParserState{} = EzParser.parse("test/test.ez")
  end
end
