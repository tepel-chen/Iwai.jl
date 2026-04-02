# Iwai

[![Build Status](https://github.com/tepel-chen/Iwai.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tepel-chen/Iwai.jl/actions/workflows/CI.yml?query=branch%3Amain)

Jinja-like template engine for Julia.

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
