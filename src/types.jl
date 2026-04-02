"""
    Template

Compiled Iwai template.

`Template` objects are callable. Pass a `NamedTuple` or dictionary-like value as
the render context.
"""
mutable struct Template{F}
    source::String
    render::F
    warmed::Bool
    optimize_buffer_size::Bool
    max_output_bytes::Int
    autoescape::Bool
    path::Union{Nothing,String}
end

to_context(init::NamedTuple) = init

function to_context(init::AbstractDict)
    return (; (Symbol(key) => value for (key, value) in pairs(init))...)
end

"""
    template(; init = (;))
    template(init)

Render a compiled template with the given context.

`init` may be a `NamedTuple` or an `AbstractDict`.
"""
function (template::Template)(; init = (;))
    return invoke_template(template, to_context(init))
end

function (template::Template)(init)
    return invoke_template(template, to_context(init))
end

function invoke_template(template::Template, ctx)
    if template.warmed
        return update_template_size!(template, template.render(template, ctx))
    end

    result = Base.invokelatest(template.render, template, ctx)
    template.warmed = true
    return update_template_size!(template, result)
end

function update_template_size!(template::Template, result::String)::String
    if template.optimize_buffer_size
        size = ncodeunits(result)
        if size > template.max_output_bytes
            template.max_output_bytes = size
        end
    end
    return result
end
