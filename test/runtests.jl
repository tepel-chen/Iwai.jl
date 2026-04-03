using IwaiEngine
using Test

@testset "IwaiEngine.jl" begin
    template = IwaiEngine.parse("Hello {{ name }}!")
    @test template((name = "Iwai",)) == "Hello Iwai!"

    table_template = IwaiEngine.parse("""
<table>
{% for row in table %}
<tr>{% for col in row %}<td>{{ col }}</td>{% end %}</tr>
{% end %}
</table>
""")
    compact_table = replace(table_template((table = [[1, 2], [3, 4]],)), r"\s+" => "")
    @test compact_table == "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>"

    teams_template = IwaiEngine.parse("""
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

    sized = IwaiEngine.parse("Hello {{ name }}"; optimize_buffer_size = true)
    @test sized.max_output_bytes == 0
    @test sized((name = "Iwai",)) == "Hello Iwai"
    @test sized.max_output_bytes == ncodeunits("Hello Iwai")
    @test sized((name = "Iwa",)) == "Hello Iwa"
    @test sized.max_output_bytes == ncodeunits("Hello Iwai")

    unsized = IwaiEngine.parse("Hello {{ name }}"; optimize_buffer_size = false)
    @test unsized((name = "Iwai",)) == "Hello Iwai"
    @test unsized.max_output_bytes == 0

    extras = IwaiEngine.parse("""
{# comment #}
{% raw %}{{ untouched }}{% endraw %}
{% set title = name|upper %}
{{ title }}
{{ values|join(",") }}
{{ missing|default("fallback") }}
{{ html|escape }}
""")
    extras_rendered = extras((name = "iwai", values = [1, 2, 3], html = "<b>safe?</b>"))
    @test occursin("{{ untouched }}", extras_rendered)
    @test occursin("IWAI", extras_rendered)
    @test occursin("1,2,3", extras_rendered)
    @test occursin("fallback", extras_rendered)
    @test occursin("&lt;b&gt;safe?&lt;/b&gt;", extras_rendered)

    loop_template = IwaiEngine.parse("""
{% for team in teams %}
{{ loop.index0 }}/{{ loop.index }}/{{ loop.first }}/{{ loop.last }}:{{ team.name }}
{% end %}
""")
    loop_rendered = loop_template((teams = [(name = "A",), (name = "B",)],))
    @test occursin("0/1/true/false:A", loop_rendered)
    @test occursin("1/2/false/true:B", loop_rendered)

    elif_template = IwaiEngine.parse("""
{% if value < 0 %}neg{% elif value == 0 %}zero{% else %}pos{% end %}
""")
    @test strip(elif_template((value = -1,))) == "neg"
    @test strip(elif_template((value = 0,))) == "zero"
    @test strip(elif_template((value = 1,))) == "pos"

    mktempdir() do tmpdir
        child_path = joinpath(tmpdir, "child.iwai")
        parent_path = joinpath(tmpdir, "parent.iwai")
        write(child_path, "<li>{{ item|upper }}</li>")
        write(parent_path, "<ul>{% include \"child.iwai\" %}</ul>")

        parent = IwaiEngine.load(parent_path)
        @test parent((item = "nested",)) == "<ul><li>NESTED</li></ul>"
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

    @test_throws ArgumentError IwaiEngine.parse("{% if value %}missing end")
    @test_throws ArgumentError IwaiEngine.parse("{% for item in items %}missing end")
    @test_throws ArgumentError IwaiEngine.parse("{% autoescape false %}missing end")
    @test_throws ArgumentError IwaiEngine.parse("{% else %}")
    @test_throws ArgumentError IwaiEngine.parse("{% elseif value %}")
    @test_throws ArgumentError IwaiEngine.parse("{% elif value %}")
    @test_throws ArgumentError IwaiEngine.parse("{% end %}")

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

    auto = IwaiEngine.parse("""
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

    no_auto = IwaiEngine.parse("{{ html }}"; autoescape = false)
    @test no_auto((html = "<b>x</b>",)) == "<b>x</b>"

    @testset "Literal Braces" begin
        template = IwaiEngine.parse("""
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
