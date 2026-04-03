struct SafeString
    value::String
end

function needs_html_escape(text::AbstractString)::Bool
    for byte in codeunits(text)
        if byte == UInt8('&') || byte == UInt8('<') || byte == UInt8('>') || byte == UInt8('"') || byte == UInt8('\'')
            return true
        end
    end
    return false
end

function escape_html(text::AbstractString)::String
    needs_html_escape(text) || return String(text)

    io = IOBuffer(sizehint = ncodeunits(text) + 16)
    write_escaped_html!(io, text)
    return String(take!(io))
end

escape_html(value)::String = escape_html(string(value))

function write_escaped_html!(io::IO, text::AbstractString)::Nothing
    start_index = firstindex(text)
    index = start_index

    while index <= lastindex(text)
        char = text[index]
        replacement =
            char == '&' ? "&amp;" :
            char == '<' ? "&lt;" :
            char == '>' ? "&gt;" :
            char == '"' ? "&quot;" :
            char == '\'' ? "&#39;" :
            nothing

        if replacement !== nothing
            if start_index < index
                write(io, SubString(text, start_index, prevind(text, index)))
            end
            write(io, replacement)
            start_index = nextind(text, index)
        end

        index = nextind(text, index)
    end

    if start_index <= lastindex(text)
        write(io, SubString(text, start_index, lastindex(text)))
    end

    return nothing
end

function write_value!(io::IO, value::SafeString, autoescape::Bool)::Nothing
    write(io, value.value)
    return nothing
end

function write_value!(io::IO, value::AbstractString, autoescape::Bool)::Nothing
    if autoescape && needs_html_escape(value)
        write_escaped_html!(io, value)
    else
        write(io, value)
    end
    return nothing
end

function write_value!(io::IO, value::Union{Integer,AbstractFloat,Rational,Complex,Bool}, autoescape::Bool)::Nothing
    write(io, string(value))
    return nothing
end

function write_value!(io::IO, value::Char, autoescape::Bool)::Nothing
    if autoescape
        string_value = string(value)
        if needs_html_escape(string_value)
            write_escaped_html!(io, string_value)
        else
            write(io, string_value)
        end
    else
        write(io, string(value))
    end
    return nothing
end

function write_value!(io::IO, value, autoescape::Bool)::Nothing
    if autoescape
        text = string(value)
        if needs_html_escape(text)
            write_escaped_html!(io, text)
        else
            write(io, text)
        end
    else
        write(io, string(value))
    end
    return nothing
end

function append_text!(io::IO, text::AbstractString)::Nothing
    isempty(text) || write(io, text)
    return nothing
end

function lookup_global(::Val{sym}) where {sym}
    if isdefined(@__MODULE__, sym)
        return getfield(@__MODULE__, sym)
    elseif isdefined(Base, sym)
        return getfield(Base, sym)
    elseif isdefined(Core, sym)
        return getfield(Core, sym)
    elseif isdefined(Main, sym)
        return getfield(Main, sym)
    else
        throw(UndefVarError(sym))
    end
end

@generated function lookup_symbol(ctx::NamedTuple{names}, ::Val{sym}) where {names,sym}
    if sym in names
        return :(getfield(ctx, $(QuoteNode(sym))))
    else
        return :(lookup_global(Val($(QuoteNode(sym)))))
    end
end

function apply_filter(::Val{:upper}, value)
    return uppercase(string(value))
end

function apply_filter(::Val{:lower}, value)
    return lowercase(string(value))
end

function apply_filter(::Val{:trim}, value)
    return strip(string(value))
end

function apply_filter(::Val{:length}, value)
    return length(value)
end

function apply_filter(::Val{:default}, value, fallback)
    if value === nothing || value === missing
        return fallback
    elseif value isa AbstractString && isempty(value)
        return fallback
    else
        return value
    end
end

function apply_filter(::Val{:join}, value, delimiter = "")
    return join(value, delimiter)
end

apply_filter(::Val{:escape}, value) = SafeString(escape_html(value))

apply_filter(::Val{:safe}, value) = SafeString(string(value))

function apply_filter(::Val{sym}, value, args...) where {sym}
    fn = lookup_global(Val(sym))
    return fn(value, args...)
end

function include_context(ctx::NamedTuple, locals)
    return (; pairs(ctx)..., locals...)
end

function default_template_root(current_path::Union{Nothing,AbstractString})::Union{Nothing,String}
    current_path === nothing && return nothing
    return canonical_template_root(dirname(abspath(String(current_path))))
end

function canonical_template_root(root::AbstractString)::String
    candidate = abspath(String(root))
    ispath(candidate) || throw(ArgumentError("template root does not exist: " * String(root)))
    return realpath(candidate)
end

function is_within_template_root(path::AbstractString, root::AbstractString)::Bool
    normalized_path = realpath(String(path))
    normalized_root = realpath(String(root))
    if normalized_path == normalized_root
        return true
    end
    return startswith(normalized_path, normalized_root * string(Base.Filesystem.path_separator))
end

function resolve_template_path(current_path::AbstractString, include_path::AbstractString; root::Union{Nothing,String} = nothing)::String
    base_dir = dirname(abspath(String(current_path)))
    root_dir = root === nothing ? default_template_root(current_path) : canonical_template_root(root)
    candidate = normpath(joinpath(base_dir, String(include_path)))
    ispath(candidate) || throw(ArgumentError("template path does not exist: " * String(include_path)))

    resolved = realpath(candidate)
    root_dir === nothing || is_within_template_root(resolved, root_dir) || throw(ArgumentError("template path escapes root"))
    return resolved
end

function render_include(template, include_path, ctx, locals)
    template.path === nothing && throw(ArgumentError("include requires a file-backed template"))
    child_path = resolve_template_path(template.path, String(include_path); root = template.root)
    child = load(child_path; optimize_buffer_size = template.optimize_buffer_size, autoescape = template.autoescape, root = template.root)
    return child(include_context(ctx, locals))
end

function truncate_suffix!(io::IOBuffer, suffix::AbstractString)::Nothing
    length(suffix) == 0 && return nothing
    truncate(io, position(io) - ncodeunits(suffix))
    return nothing
end

function create_output_buffer(template)::IOBuffer
    if template.optimize_buffer_size && template.max_output_bytes > 0
        return IOBuffer(sizehint = template.max_output_bytes)
    end
    return IOBuffer()
end

function try_length(iterable)
    try
        return length(iterable)
    catch
        return nothing
    end
end
