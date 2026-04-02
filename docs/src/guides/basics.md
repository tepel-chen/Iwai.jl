# Basics

## Parsing from Strings

```@example
using Iwai

template = Iwai.parse("Hello {{ name }}!")
template((name = "Iwai",))
```

## Loading from Files

`Iwai.load` caches compiled templates by file path and mtime.

```julia
template = Iwai.load("views/index.iwai")
html = template((title = "Home",))
```

## Context Values

Render contexts may be passed as `NamedTuple`s or dictionaries.

```@example
using Iwai

template = Iwai.parse("{{ title }} / {{ count }}")
template(Dict(:title => "Todos", :count => 3))
```

## Filters

```@example
using Iwai

template = Iwai.parse("""
{{ name|upper }}
{{ missing|default("fallback") }}
{{ values|join(", ") }}
""")

template((name = "iwai", values = [1, 2, 3]))
```

## Autoescape

Autoescape is enabled by default for `{{ ... }}` expressions.

```@example
using Iwai

template = Iwai.parse("""
{{ html }}
{{ html|safe }}
{% autoescape false %}
{{ html }}
{% end %}
""")

template((html = "<b>x</b>",))
```
