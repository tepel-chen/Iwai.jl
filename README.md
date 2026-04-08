# IwaiEngine

[![Build Status](https://github.com/tepel-chen/IwaiEngine.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tepel-chen/IwaiEngine.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tepel-chen.github.io/Iwai.jl/dev/)

Jinja-like template engine for Julia.

Published docs:

- https://tepel-chen.github.io/Iwai.jl/dev/

IwaiEngine uses `NamedTuple` render contexts. Dictionary-based render contexts are not
supported.

Current features:

- `{{ expr }}` expressions
- `{% if %}`, `{% elif %}`, `{% else %}`, `{% end %}`
- `{% for x in xs %} ... {% end %}` with `loop.index`, `loop.index0`, `loop.first`, `loop.last`, `loop.length`
- `{% set name = expr %}`
- `{% include "partial.iwai" %}`
- `{% extends "base.iwai" %}` and `{% block name %}...{% end %}`
- `{% autoescape false %}...{% end %}`
- `{# comment #}` and `{% raw %}...{% endraw %}`
- autoescape enabled by default
- filters such as `upper`, `lower`, `trim`, `length`, `join`, `default`, `escape`, `safe`

Benchmark:

| Case | Engine | ns/iter |
| --- | --- | ---: |
| Big table | IwaiEngine | 312068 |
| Big table | Mustache | 21651265 |
| Big table | HAML | 1090643 |
| Big table | OteraEngine | 145017052 |
| Teams | IwaiEngine | 312 |
| Teams | Mustache | 30675 |
| Teams | HAML | 12069 |
| Teams | OteraEngine | 2490 |

Benchmark source:

- https://github.com/tepel-chen/julia_template_benchmark
