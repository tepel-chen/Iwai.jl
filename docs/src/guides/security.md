# Security

Iwai is intended for trusted templates.

## Autoescape

`{{ ... }}` expressions are HTML-escaped by default. Use `|safe` only for
content that is already trusted and sanitized.

```julia
template = Iwai.parse("{{ html }} {{ html|safe }}")
```

Autoescape is HTML-text oriented. It does not perform context-aware escaping for
JavaScript, CSS, or attribute-specific contexts.

## Template Paths

Relative `{% include %}` and `{% extends %}` paths are resolved from the
template's own directory. Iwai uses normalized real paths and refuses templates
that escape that root, including symlink-based escapes.

## Trusted Template Assumption

Iwai compiles templates into Julia functions. That is appropriate when the
application owns the templates, but it is not a sandbox for untrusted template
authors.
