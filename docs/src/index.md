# Iwai.jl

Jinja-like template engine for Julia.

Iwai compiles templates to Julia functions. It supports a compact Jinja-style
syntax while staying fast enough for server-side rendering workloads.

## Features

- `{{ expr }}` expressions
- `{% if %}`, `{% elif %}`, `{% else %}`, `{% end %}`
- `{% for x in xs %} ... {% end %}` with `loop.index`, `loop.index0`, `loop.first`, `loop.last`, `loop.length`
- `{% set name = expr %}`
- `{% include "partial.iwai" %}`
- `{% extends "base.iwai" %}` and `{% block name %} ... {% end %}`
- `{% autoescape false %} ... {% end %}`
- `{# comment #}` and `{% raw %} ... {% endraw %}`
- filters such as `upper`, `lower`, `trim`, `length`, `join`, `default`, `escape`, `safe`

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/tepel-chen/Iwai.jl")
```

## Quick Start

```@example
using Iwai

template = Iwai.parse("""
<ul>
{% for team in teams %}
  <li>{{ loop.index }}. {{ team.name }} - {{ team.score }}</li>
{% end %}
</ul>
""")

template((
    teams = [
        (name = "Jiangsu", score = 43),
        (name = "Beijing", score = 27),
    ],
))
```

See the guides for file-backed templates, inheritance, and escaping behavior.
