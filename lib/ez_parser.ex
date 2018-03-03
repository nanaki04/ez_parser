defmodule EzParser do
  alias CodeParserState, as: State
  @behaviour State.Parser

  @type parser_state :: State.state
  @type file_path :: State.Parser.file_path
  @type state :: %EzParser{
    parser_state: parser_state,
    current_item: {atom, atom}
  }

  defstruct parser_state: %State{},
    current_item: {:undefined, :undefined}

  @impl(State.Parser)
  def parse(file_path) do
    State.add_file(%State{}, %State.File{name: file_path})
    |> (&Map.put %EzParser{}, :parser_state, &1).()
    |> parse_namespaces
    |> Map.fetch!(:parser_state)
  end

  @spec parse_namespaces(state) :: state
  defp parse_namespaces(state) do
    state.parser_state
    |> State.File.name
    |> File.read!
    |> String.split("\n")
    |> Enum.reduce(state, &transform(&2, &1))
  end

  @spec transform(state, String.t) :: state
  defp transform(state, line) do
    line
    |> String.trim
    |> replace_global_aliases
    |> (&parse_line state, &1).()
  end

  @spec replace_global_aliases(String.t) :: String.t
  defp replace_global_aliases(line) do
    line
    |> String.replace(~r/(?<=\s)ob-(\w+)(?=\s)/, "IObservable<\\1>")
    |> String.replace(~r/(?<=^)ob-(\w+)(?=\s)/, "IObservable<\\1>")
    |> String.replace(~r/(?<=\s)_ob-(\w+)(?=\s)/, "_IObservable<\\1>")
    |> String.replace(~r/(?<=^)_ob-(\w+)(?=\s)/, "_IObservable<\\1>")
    |> String.replace(~r/(?<=\s)l-(\w+)(?=\s)/, "List<\\1>")
    |> String.replace(~r/(?<=^)l-(\w+)(?=\s)/, "List<\\1>")
    |> String.replace(~r/(?<=\s)_l-(\w+)(?=\s)/, "_List<\\1>")
    |> String.replace(~r/(?<=^)_l-(\w+)(?=\s)/, "_List<\\1>")
    |> String.replace(~r/<i>/, "<int>")
    |> String.replace(~r/<f>/, "<float>")
    |> String.replace(~r/<s>/, "<string>")
    |> String.replace(~r/<b>/, "<bool>")
    |> String.replace(~r/\[i\]/, "int[]")
    |> String.replace(~r/\[s\]/, "string[]")
    |> String.replace(~r/\[f\]/, "float[]")
    |> String.replace(~r/\[b\]/, "bool[]")
  end

  @spec parse_line(state, String.t) :: state
  defp parse_line(state, "ns " <> namespace) do
    state.parser_state
    |> State.File.add_namespace(%State.Namespace{})
    |> State.Namespace.set_name(parse_name namespace)
    |> (&Map.put state, :parser_state, &1).()
  end

  defp parse_line(state, "c " <> class) do
    state = %{state | current_item: {State.Class, State.ClassMethod}}
    state.parser_state
    |> State.Namespace.add_class(%State.Class{})
    |> State.Class.set_name(parse_name class)
    |> State.Class.set_description(parse_description class)
    |> (&Map.put state, :parser_state, &1).()
  end

  defp parse_line(state, "e " <> enum) do
    state = %{state | current_item: {State.Enum, nil}}
    state.parser_state
    |> State.Namespace.add_enum(%State.Enum{})
    |> State.Enum.set_name(parse_name enum)
    |> State.Enum.set_description(parse_description enum)
    |> (&Map.put state, :parser_state, &1).()
  end

  defp parse_line(state, "if " <> interface) do
    state = %{state | current_item: {State.Interface, State.InterfaceMethod}}
    state.parser_state
    |> State.Namespace.add_interface(%State.Interface{})
    |> State.Interface.set_name(parse_name interface)
    |> State.Interface.set_description(parse_description interface)
    |> (&Map.put state, :parser_state, &1).()
  end

  defp parse_line(state, "i " <> int) do
    parse_method_or_property(state, "public", "int", int)
  end

  defp parse_line(state, "s " <> string) do
    parse_method_or_property(state, "public", "string", string)
  end

  defp parse_line(state, "f " <> float) do
    parse_method_or_property(state, "public", "float", float)
  end

  defp parse_line(state, "b " <> float) do
    parse_method_or_property(state, "public", "bool", float)
  end

  defp parse_line(state, "_i " <> int) do
    parse_method_or_property(state, "private", "int", int)
  end

  defp parse_line(state, "_s " <> string) do
    parse_method_or_property(state, "private", "string", string)
  end

  defp parse_line(state, "_f " <> float) do
    parse_method_or_property(state, "private", "float", float)
  end

  defp parse_line(state, "_b " <> float) do
    parse_method_or_property(state, "private", "bool", float)
  end

  defp parse_line(state, custom) do
    case Regex.match?(~r/(?<=^)_\w+/, custom) do
      true -> "private"
      false -> "public"
    end
    |> (&parse_method_or_property(state, &1, parse_custom_type(custom), custom)).()
  end

  @spec parse_method_or_property(state, String.t, String.t, String.t) :: state
  defp parse_method_or_property(state, accessibility, type, line) do
    case is_method(line) do
      true -> parse_method(state, accessibility, type, line)
      false -> parse_property(state, accessibility, type, line)
    end
  end

  @spec parse_method(state, String.t, String.t, String.t) :: state
  defp parse_method(state, accessibility, type, line) do
    state.parser_state
    |> elem(state.current_item, 0).add_method(%State.Method{}
      |> State.Method.set_type(type)
      |> State.Method.set_accessibility(accessibility)
      |> State.Method.set_name(parse_name line)
      |> State.Method.set_description(parse_description line)
    )
    |> (&Map.put state, :parser_state, &1).()
    |> (fn state -> Regex.run(~r/(?<=\().*(?=\))/, line)
      |> hd
      |> String.split(", ")
      |> Enum.reduce(state, fn parameter, state -> parse_method_parameter(state, parameter) end)
    end).()
  end

  @spec parse_method_parameter(state, String.t) :: state
  defp parse_method_parameter(state, ""), do: state

  defp parse_method_parameter(state, "i " <> int) do
    parse_method_parameter(state, "int", int)
  end

  defp parse_method_parameter(state, "s " <> int) do
    parse_method_parameter(state, "string", int)
  end

  defp parse_method_parameter(state, "f " <> int) do
    parse_method_parameter(state, "float", int)
  end

  defp parse_method_parameter(state, "b " <> int) do
    parse_method_parameter(state, "bool", int)
  end

  defp parse_method_parameter(state, custom) do
    parse_method_parameter(state, parse_custom_type(custom), custom)
  end

  defp parse_method_parameter(state, type, line) do
    state.parser_state
    |> elem(state.current_item, 1).add_parameter(%State.Property{}
      |> State.Property.set_type(type)
      |> State.Property.set_accessibility("public")
      |> State.Property.set_name(parse_name line)
    )
    |> (&Map.put state, :parser_state, &1).()
  end

  @spec parse_property(state, String.t, String.t, String.t) :: state
  defp parse_property(state, accessibility, type, line) do
    state.parser_state
    |> elem(state.current_item, 0).add_property(%State.Property{}
      |> State.Property.set_type(type)
      |> State.Property.set_accessibility(accessibility)
      |> State.Property.set_name(parse_name line)
      |> State.Property.set_description(parse_description line)
    )
    |> (&Map.put state, :parser_state, &1).()
  end

  @spec parse_custom_type(String.t) :: String.t
  defp parse_custom_type(line) do
    (Regex.run(~r/(?<=^)[\w<>]+(?=\s)/, line) || ["var"]) |> hd
  end

  @spec parse_name(String.t) :: String.t
  defp parse_name(line) do
    (Regex.run(~r/[.\w]+(?=$)|[.\w]+(?=\s#)|[.\w]+(?=\()/, line) || [""]) |> hd
  end

  @spec parse_description(String.t) :: String.t
  defp parse_description(line) do
    (Regex.run(~r/(?<=#\s).+(?=$)/, line) || ["TODO"]) |> hd
  end

  @spec is_method(String.t) :: boolean
  defp is_method(line) do
    Regex.match? ~r/\(.*\)/, line
  end
end
