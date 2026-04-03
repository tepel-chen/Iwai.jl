const TEMPLATE_CACHE = Dict{Tuple{String,Bool,Bool,Union{Nothing,String}},Tuple{Float64,Template}}()
const TEMPLATE_CACHE_LOCK = ReentrantLock()

"""
    load(path; optimize_buffer_size = true, autoescape = true, root = nothing) -> Template

Load and compile a file-backed IwaiEngine template.

Templates are cached by absolute path, mtime, `optimize_buffer_size`,
`autoescape`, and `root`. Relative `{% include %}` and `{% extends %}` paths
are resolved from the current file's directory and are prevented from escaping
the configured root.
"""
function load(path::AbstractString; optimize_buffer_size::Bool = true, autoescape::Bool = true, root::Union{Nothing,String} = nothing)::Template
    resolved = abspath(String(path))
    stat_mtime = mtime(resolved)
    normalized_root = root === nothing ? default_template_root(resolved) : canonical_template_root(root)
    cache_key = (resolved, optimize_buffer_size, autoescape, normalized_root)

    lock(TEMPLATE_CACHE_LOCK) do
        cached = get(TEMPLATE_CACHE, cache_key, nothing)
        if cached !== nothing && cached[1] == stat_mtime
            return cached[2]
        end

        template = parse(read(resolved, String); optimize_buffer_size = optimize_buffer_size, autoescape = autoescape, path = resolved, root = normalized_root)
        TEMPLATE_CACHE[cache_key] = (stat_mtime, template)
        return template
    end
end
