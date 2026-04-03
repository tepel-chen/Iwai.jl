using IwaiEngine
using Test

struct BrokenLengthIter
    data::Vector{Int}
end

Base.iterate(iter::BrokenLengthIter) = isempty(iter.data) ? nothing : (iter.data[1], 2)
Base.iterate(iter::BrokenLengthIter, state::Int) = state > length(iter.data) ? nothing : (iter.data[state], state + 1)
Base.length(::BrokenLengthIter) = error("broken length")

struct NoLengthIter
    data::Vector{Int}
end

Base.iterate(iter::NoLengthIter) = isempty(iter.data) ? nothing : (iter.data[1], 2)
Base.iterate(iter::NoLengthIter, state::Int) = state > length(iter.data) ? nothing : (iter.data[state], state + 1)

function load_template(source::AbstractString; name::AbstractString = "template.iwai", root::Union{Nothing,String} = nothing, kwargs...)
    tmpdir = mktempdir()
    path = joinpath(tmpdir, name)
    write(path, String(source))
    return IwaiEngine.load(path; root = root === nothing ? tmpdir : root, kwargs...)
end

@testset "IwaiEngine.jl" begin
    template = load_template("Hello {{ name }}!")
    @test template((name = "Iwai",)) == "Hello Iwai!"

    table_template = load_template("""
<table>
{% for row in table %}
<tr>{% for col in row %}<td>{{ col }}</td>{% end %}</tr>
{% end %}
</table>
""")
    compact_table = replace(table_template((table = [[1, 2], [3, 4]],)), r"\s+" => "")
    @test compact_table == "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>"

    teams_template = load_template("""
<ul>
{% for team in teams %}
<li class="{% if team.champion %}champion{% end %}">{{ team.name }}: {{ team.score }}</li>
{% end %}
</ul>
""")
    rendered = teams_template((
        teams = [
            (name = "Jiangsu", score = 43, champion = true),
            (name = "Beijing", score = 27, champion = false),
        ],
    ))
    @test occursin("class=\"champion\"", rendered)
    @test occursin("Beijing: 27", rendered)

    mktempdir() do tmpdir
        template_path = joinpath(tmpdir, "hello.iwai")
        write(template_path, "Count {{ count }}")

        first_loaded = IwaiEngine.load(template_path)
        second_loaded = IwaiEngine.load(template_path)
        @test first_loaded === second_loaded
        @test first_loaded((count = 1,)) == "Count 1"

        sleep(1.1)
        write(template_path, "Count {{ count }}!")
        reloaded = IwaiEngine.load(template_path)
        @test reloaded !== first_loaded
        @test reloaded((count = 2,)) == "Count 2!"
    end

    @test_throws ArgumentError template(Dict(:name => "Iwai"))

    sized = load_template("Hello {{ name }}!"; optimize_buffer_size = true)
    @test sized.max_output_bytes == 0
    @test sized((name = "Iwai",)) == "Hello Iwai!"
    @test sized.max_output_bytes == ncodeunits("Hello Iwai!")
    @test sized((name = "Iwa",)) == "Hello Iwa!"
    @test sized.max_output_bytes == ncodeunits("Hello Iwai!")

    unsized = load_template("Hello {{ name }}!"; optimize_buffer_size = false)
    @test unsized((name = "Iwai",)) == "Hello Iwai!"
    @test unsized.max_output_bytes == 0

    extras = load_template("""
{# comment #}
{% raw %}{{ untouched }}{% endraw %}
{% set title = name|upper %}
{{ title }}
{{ name|lower }}
{{ title|trim }}
{{ values|length }}
{{ values|join(",") }}
{{ empty|default("fallback") }}
{{ nothing_value|default("fallback") }}
{{ missing_value|default("fallback") }}
{{ zero_value|default("fallback") }}
{{ false_value|default("fallback") }}
{{ values|join }}
{{ html|escape }}
{{ html|safe }}
""")
    extras_rendered = extras((
        name = "iwai",
        values = [1, 2, 3],
        html = "<b>safe?</b>",
        empty = "",
        nothing_value = nothing,
        missing_value = missing,
        zero_value = 0,
        false_value = false,
    ))
    @test occursin("{{ untouched }}", extras_rendered)
    @test occursin("IWAI", extras_rendered)
    @test occursin("iwai", extras_rendered)
    @test occursin("3", extras_rendered)
    @test occursin("1,2,3", extras_rendered)
    @test occursin("fallback", extras_rendered)
    @test occursin("0", extras_rendered)
    @test occursin("false", extras_rendered)
    @test occursin("&lt;b&gt;safe?&lt;/b&gt;", extras_rendered)
    @test occursin("<b>safe?</b>", extras_rendered)

    default_template = load_template("""
{{ nothing_value|default("fallback") }}
{{ missing_value|default("fallback") }}
{{ empty|default("fallback") }}
{{ zero_value|default("fallback") }}
{{ false_value|default("fallback") }}
""")
    default_rendered = split(strip(default_template((
        nothing_value = nothing,
        missing_value = missing,
        empty = "",
        zero_value = 0,
        false_value = false,
    ))), '\n')
    @test default_rendered[1] == "fallback"
    @test default_rendered[2] == "fallback"
    @test default_rendered[3] == "fallback"
    @test default_rendered[4] == "0"
    @test default_rendered[5] == "false"

    @test load_template("{{ values|length }}")((values = Int[],)) == "0"
    @test load_template("{{ values|join }}")((values = ["a", "b"],)) == "ab"
    @test load_template("{{ values|join(\",\") }}")((values = ["a", "b"],)) == "a,b"
    @test load_template("{{ html|escape }}")((html = "<x>",)) == "&lt;x&gt;"
    @test load_template("{{ html|safe }}")((html = "<x>",)) == "<x>"
    @test load_template("{{ html|escape }}")((html = "a&b",)) == "a&amp;b"
    @test load_template("{{ length(values) }}")((values = [1, 2, 3],)) == "3"
    @test load_template("{{ ifelse(flag, \"yes\", \"no\") }}")((flag = true,)) == "yes"
    @eval Main global iwai_engine_main_helper = "main-only"
    @test_throws UndefVarError load_template("{{ iwai_engine_main_helper }}")((;))
    @test_throws UndefVarError load_template("{{ summarysize(values) }}")((values = [1, 2, 3],))

    loop_template = load_template("""
{% for team in teams %}
{{ loop.index0 }}/{{ loop.index }}/{{ loop.first }}/{{ loop.last }}:{{ team.name }}
{% end %}
""")
    loop_rendered = loop_template((teams = [(name = "A",), (name = "B",)],))
    @test occursin("0/1/true/false:A", loop_rendered)
    @test occursin("1/2/false/true:B", loop_rendered)

    stream_template = load_template("""
{% for item in items %}
{{ loop.last }}:{{ item }}
{% end %}
""")
    stream_rendered = replace(stream_template((items = NoLengthIter([1, 2, 3]),)), r"\s+" => "")
    @test occursin("false:1", stream_rendered)
    @test occursin("false:2", stream_rendered)
    @test occursin("false:3", stream_rendered)
    @test IwaiEngine.try_length(NoLengthIter([1, 2, 3])) === nothing
    @test IwaiEngine.try_length([1, 2, 3]) == 3
    @test_throws ErrorException IwaiEngine.try_length(BrokenLengthIter([1, 2, 3]))

    pair_template = load_template("""
{% for key, value in pairs %}
{{ key }}={{ value }}
{% end %}
""")
    pair_rendered = replace(pair_template((pairs = [("alpha", 1), ("beta", 2)],)), r"\s+" => "")
    @test occursin("alpha=1", pair_rendered)
    @test occursin("beta=2", pair_rendered)

    elif_template = load_template("""
{% if value < 0 %}neg{% elif value == 0 %}zero{% else %}pos{% end %}
""")
    @test strip(elif_template((value = -1,))) == "neg"
    @test strip(elif_template((value = 0,))) == "zero"
    @test strip(elif_template((value = 1,))) == "pos"
    @test strip(elif_template((value = 2,))) == "pos"
    @test_throws UndefVarError load_template("{{ iwai_missing_symbol }}")((;))

    nested_if = load_template("""
{% if outer %}
outer
{% if inner %}
inner
{% else %}
inner-miss
{% end %}
{% elif fallback %}
fallback
{% else %}
none
{% end %}
""")
    @test occursin("outer", nested_if((outer = true, inner = true, fallback = false)))
    @test occursin("inner", nested_if((outer = true, inner = true, fallback = false)))
    @test occursin("inner-miss", nested_if((outer = true, inner = false, fallback = false)))
    @test occursin("fallback", strip(nested_if((outer = false, inner = false, fallback = true))))
    @test occursin("none", strip(nested_if((outer = false, inner = false, fallback = false))))

    multi_elif = load_template("""
{% if score < 10 %}low{% elif score < 20 %}mid{% elif score < 30 %}high{% else %}top{% end %}
""")
    @test strip(multi_elif((score = 5,))) == "low"
    @test strip(multi_elif((score = 15,))) == "mid"
    @test strip(multi_elif((score = 25,))) == "high"
    @test strip(multi_elif((score = 35,))) == "top"

    mktempdir() do tmpdir
        child_path = joinpath(tmpdir, "child.iwai")
        parent_path = joinpath(tmpdir, "parent.iwai")
        write(child_path, "<li>{{ item|upper }}</li>")
        write(parent_path, "<ul>{% include \"child.iwai\" %}</ul>")

        parent = IwaiEngine.load(parent_path)
        @test parent((item = "nested",)) == "<ul><li>NESTED</li></ul>"
    end

    mktempdir() do tmpdir
        mkpath(joinpath(tmpdir, "partials"))
        write(joinpath(tmpdir, "partials", "hello.iwai"), "<span>Hello</span>")
        write(joinpath(tmpdir, "page.iwai"), "<div>{% include \"partials/hello.iwai\" %}</div>")

        page = IwaiEngine.load(joinpath(tmpdir, "page.iwai"); root = tmpdir)
        @test page((;)) == "<div><span>Hello</span></div>"
    end

    mktempdir() do tmpdir
        parent_path = joinpath(tmpdir, "parent.iwai")
        escaped_path = joinpath(tmpdir, "..", "escaped.iwai")
        write(parent_path, "{% include \"../escaped.iwai\" %}")
        write(escaped_path, "escaped")

        err = try
            IwaiEngine.load(parent_path)((;))
            nothing
        catch caught
            caught
        end
        @test err isa ArgumentError
        @test occursin("template path escapes root", sprint(showerror, err))
    end

    mktempdir() do tmpdir
        outside_dir = mktempdir()
        outside_path = joinpath(outside_dir, "outside.iwai")
        link_path = joinpath(tmpdir, "linked.iwai")
        parent_path = joinpath(tmpdir, "parent.iwai")

        write(outside_path, "outside")
        symlink(outside_path, link_path)
        write(parent_path, "{% include \"linked.iwai\" %}")

        err = try
            IwaiEngine.load(parent_path)((;))
            nothing
        catch caught
            caught
        end
        @test err isa ArgumentError
        @test occursin("template path escapes root", sprint(showerror, err))
    end

    mktempdir() do tmpdir
        base_path = joinpath(tmpdir, "base.iwai")
        child_path = joinpath(tmpdir, "child.iwai")

        write(base_path, """
<html>
  <body>
    {% block header %}<h1>Base</h1>{% end %}
    {% block content %}<p>Base content</p>{% end %}
  </body>
</html>
""")

        write(child_path, """
{% extends "base.iwai" %}
{% block content %}
<p>Hello {{ name }}</p>
{% end %}
""")

        child = IwaiEngine.load(child_path)
        rendered = child((name = "Iwai",))
        @test occursin("<h1>Base</h1>", rendered)
        @test occursin("<p>Hello Iwai</p>", rendered)
        @test !occursin("Base content", rendered)
    end

    mktempdir() do tmpdir
        base_path = joinpath(tmpdir, "base.iwai")
        child_path = joinpath(tmpdir, "child.iwai")

        write(base_path, """
<main>
  {% block content %}<p>Base content</p>{% end %}
</main>
""")

        write(child_path, """
{% extends "base.iwai" %}
{% block content %}
<section>
  {% block inner %}<p>Inner default</p>{% end %}
</section>
{% end %}
""")

        child = IwaiEngine.load(child_path)
        rendered = child((;))
        @test occursin("<section>", rendered)
        @test occursin("Inner default", rendered)
        @test !occursin("Base content", rendered)
    end

    mktempdir() do tmpdir
        mkpath(joinpath(tmpdir, "layouts"))
        mkpath(joinpath(tmpdir, "admin", "posts"))
        base_path = joinpath(tmpdir, "layouts", "base.iwai")
        child_path = joinpath(tmpdir, "admin", "posts", "edit.iwai")

        write(base_path, """
<html>
  <body>
    {% block content %}<p>Base content</p>{% end %}
  </body>
</html>
""")
        write(child_path, """
{% extends "../../layouts/base.iwai" %}
{% block content %}
<p>Hello {{ name }}</p>
{% end %}
""")

        child = IwaiEngine.load(child_path; root = tmpdir)
        rendered = child((name = "Nested",))
        @test occursin("<p>Hello Nested</p>", rendered)
        @test !occursin("Base content", rendered)
    end

    mktempdir() do tmpdir
        base_path = joinpath(tmpdir, "base.iwai")
        child_path = joinpath(tmpdir, "child.iwai")

        write(base_path, """
<section>
  {% block content %}<p>Base</p>{% end %}
</section>
""")

        write(child_path, """
{% extends "base.iwai" %}
{% block content %}
<ul>
{% for item in items %}
  {% if item.show %}<li>{{ item.name }}</li>{% end %}
{% end %}
</ul>
{% end %}
""")

        child = IwaiEngine.load(child_path)
        rendered = child((items = [(name = "A", show = true), (name = "B", show = false)],))
        @test occursin("<li>A</li>", replace(rendered, r"\s+" => ""))
        @test !occursin("<li>B</li>", replace(rendered, r"\s+" => ""))
        @test !occursin("Base", rendered)
    end

    mktempdir() do tmpdir
        write(joinpath(tmpdir, "child.iwai"), "{% extends \"../base.iwai\" %}")
        write(joinpath(tmpdir, "..", "base.iwai"), "<p>escaped</p>")

        err = try
            IwaiEngine.load(joinpath(tmpdir, "child.iwai"))
            nothing
        catch caught
            caught
        end
        @test err isa ArgumentError
        @test occursin("template path escapes root", sprint(showerror, err))
    end

    @test_throws ArgumentError load_template("{% if value %}missing end")
    @test_throws ArgumentError load_template("{% for item in items %}missing end")
    @test_throws ArgumentError load_template("{% autoescape false %}missing end")
    @test_throws ArgumentError load_template("{% else %}")
    @test_throws ArgumentError load_template("{% elseif value %}")
    @test_throws ArgumentError load_template("{% elif value %}")
    @test_throws ArgumentError load_template("{% end %}")
    @test_throws ArgumentError load_template("{{ @time name }}")
    @test_throws ArgumentError load_template("{{ name")
    @test_throws ArgumentError load_template("{# comment")
    @test_throws ArgumentError load_template("{% if value %}")
    @test_throws ArgumentError load_template("{% raw %}raw")
    @test_throws ArgumentError load_template("{% switch %}")
    @test_throws ArgumentError load_template("{% if flag %}{% else if other %}x{% end %}")

    raw_empty = IwaiEngine.parse("{% raw %}{% endraw %}")
    @test raw_empty((;)) == ""

    mixed_loop = load_template("""
{% for item in items %}
{{ item }}{% set ignored = 1 %}
{% end %}
""")
    @test replace(mixed_loop((items = [1, 2],)), r"\s+" => "") == "12"

    mktempdir() do tmpdir
        broken_path = joinpath(tmpdir, "broken.iwai")
        write(broken_path, "{% block content %}broken")

        err = try
            IwaiEngine.load(broken_path)
            nothing
        catch caught
            caught
        end
        @test err isa ArgumentError
        @test occursin("Unclosed block", sprint(showerror, err))
    end

    mktempdir() do tmpdir
        mkpath(joinpath(tmpdir, "partials"))
        mkpath(joinpath(tmpdir, "pages"))
        write(joinpath(tmpdir, "partials", "nav.iwai"), "<nav>{{ title }}</nav>")
        write(joinpath(tmpdir, "pages", "home.iwai"), "{% include \"../partials/nav.iwai\" %}")

        home = IwaiEngine.load(joinpath(tmpdir, "pages", "home.iwai"); root = tmpdir)
        @test home((title = "Docs",)) == "<nav>Docs</nav>"
    end

    mktempdir() do tmpdir
        mkpath(joinpath(tmpdir, "partials"))
        write(joinpath(tmpdir, "partials", "badge.iwai"), "<span>{{ title }} / {{ loop.index }}</span>")
        write(joinpath(tmpdir, "page.iwai"), """
{% set title = name|upper %}
{% for item in items %}
{% include "partials/badge.iwai" %}
{% end %}
""")

        page = IwaiEngine.load(joinpath(tmpdir, "page.iwai"); root = tmpdir)
        rendered = replace(page((name = "docs", items = [1, 2])), r"\s+" => "")
        @test occursin("<span>DOCS/1</span>", rendered)
        @test occursin("<span>DOCS/2</span>", rendered)
    end

    auto = load_template("""
{{ html }}
{{ html|safe }}
{{ html|escape }}
{% autoescape false %}
{{ html }}
{{ html|escape }}
{% end %}
""")
    auto_rendered = auto((html = "<b>x</b>",))
    @test occursin("&lt;b&gt;x&lt;/b&gt;", auto_rendered)
    @test occursin("<b>x</b>", auto_rendered)
    @test count(occursin("&lt;b&gt;x&lt;/b&gt;", line) for line in split(auto_rendered, '\n')) >= 2

    no_auto = load_template("{{ html }}"; autoescape = false)
    @test no_auto((html = "<b>x</b>",)) == "<b>x</b>"

    @testset "Literal Braces" begin
        template = load_template("""
<script>
const theme = { accent: "#f97316", muted: "#a8a29e" };
</script>
<div class="bg-[radial-gradient(circle_at_top,_rgba(249,115,22,0.18),_transparent_34%)]">
  {{ title }}
</div>
""")

        rendered = template((title = "CMS",))
        @test occursin("const theme = { accent: \"#f97316\", muted: \"#a8a29e\" };", rendered)
        @test occursin("bg-[radial-gradient(circle_at_top,_rgba(249,115,22,0.18),_transparent_34%)]", rendered)
        @test occursin(r">\s*CMS\s*<", rendered)
    end
end
