# Inheritance

Iwai supports file-based template composition through `{% include %}`,
`{% extends %}`, and `{% block %}`.

## Include

```julia
# views/list.iwai
<ul>{% include "item.iwai" %}</ul>
```

```julia
# views/item.iwai
<li>{{ item|upper }}</li>
```

The included template receives the current render context plus any visible local
variables defined with `{% set %}`.

## Extends and Blocks

```julia
# views/base.iwai
<html>
  <body>
    {% block header %}<h1>Base</h1>{% end %}
    {% block content %}<p>Base content</p>{% end %}
  </body>
</html>
```

```julia
# views/page.iwai
{% extends "base.iwai" %}
{% block content %}
<p>Hello {{ name }}</p>
{% end %}
```

```@example
using Iwai
using Base.Filesystem: mktempdir

mktempdir() do dir
    write(joinpath(dir, "base.iwai"), """
<html>
  <body>
    {% block content %}<p>Base content</p>{% end %}
  </body>
</html>
""")
    write(joinpath(dir, "page.iwai"), """
{% extends "base.iwai" %}
{% block content %}
<p>Hello {{ name }}</p>
{% end %}
""")

    tpl = Iwai.load(joinpath(dir, "page.iwai"))
    println(tpl((name = "Iwai",)))
end
```
