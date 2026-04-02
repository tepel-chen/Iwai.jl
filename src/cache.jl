const TEMPLATE_CACHE = Dict{Tuple{String,Bool,Bool},Tuple{Float64,Template}}()
const TEMPLATE_CACHE_LOCK = ReentrantLock()

"""
    load(path; optimize_buffer_size = true, autoescape = true) -> Template

Load and compile a file-backed Iwai template.

Templates are cached by absolute path, mtime, `optimize_buffer_size`, and
`autoescape`. Relative `{% include %}` and `{% extends %}` paths are resolved
from this file's directory and are prevented from escaping that root.
"""
function load(path::AbstractString; optimize_buffer_size::Bool = true, autoescape::Bool = true)::Template
    resolved = abspath(String(path))
    stat_mtime = mtime(resolved)
    cache_key = (resolved, optimize_buffer_size, autoescape)

    lock(TEMPLATE_CACHE_LOCK) do
        cached = get(TEMPLATE_CACHE, cache_key, nothing)
        if cached !== nothing && cached[1] == stat_mtime
            return cached[2]
        end

        template = parse(read(resolved, String); optimize_buffer_size = optimize_buffer_size, autoescape = autoescape, path = resolved)
        TEMPLATE_CACHE[cache_key] = (stat_mtime, template)
        return template
    end
end
