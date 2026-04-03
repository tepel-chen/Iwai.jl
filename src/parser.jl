"""
    parse(source; optimize_buffer_size = true, autoescape = true, path = nothing, root = nothing) -> Template

Compile an IwaiEngine template from a string.

- `optimize_buffer_size=true` reuses the largest previously observed output size
  as the next render buffer hint.
- `autoescape=true` enables HTML escaping for `{{ ... }}` expressions unless the
  value is marked with the `safe` filter or rendered inside `{% autoescape false %}`.
- `path` is used to resolve relative `{% include %}` and `{% extends %}` paths.
- `root` constrains file-backed template resolution to a specific directory tree.
"""
function parse(source::AbstractString; optimize_buffer_size::Bool = true, autoescape::Bool = true, path::Union{Nothing,String} = nothing, root::Union{Nothing,String} = nothing)::Template
    normalized = String(source)
    template_root = root === nothing ? default_template_root(path) : canonical_template_root(root)
    body = compile_template(normalized, path, autoescape, template_root)
    render = eval(Expr(:->, Expr(:tuple, :(__iwai_template__), :(__iwai_init__)), body))
    return Template(normalized, render, false, optimize_buffer_size, 0, autoescape, path, template_root)
end

function compile_template(source::String, path::Union{Nothing,String} = nothing, autoescape::Bool = true, root::Union{Nothing,String} = nothing)::Expr
    tokens = preprocess_template(tokenize(source); path = path, root = root)
    body, index, _ = parse_nodes(tokens, 1, Set{String}(), Dict{Symbol,Any}(), autoescape)
    index > length(tokens) || throw(ArgumentError("Unexpected trailing template tokens"))
    statements = Any[:(io = create_output_buffer(__iwai_template__)), :(ctx = __iwai_init__)]
    append!(statements, body)
    push!(statements, :(return String(take!(io))))
    return Expr(:block, statements...)
end

function tokenize(source::String)
    tokens = Tuple{Symbol,String}[]
    cursor = firstindex(source)

    while cursor <= lastindex(source)
        open_index = findnext('{', source, cursor)
        open_index === nothing && break

        if open_index > cursor
            push!(tokens, (:text, source[cursor:prevind(source, open_index)]))
        end

        if startswith(source[open_index:end], "{{")
            close_index = findnext("}}", source, nextind(source, open_index, 2))
            close_index === nothing && throw(ArgumentError("Unclosed expression tag"))
            push!(tokens, (:expr, strip(source[nextind(source, open_index, 2):prevind(source, first(close_index))])))
            cursor = nextind(source, last(close_index))
        elseif startswith(source[open_index:end], "{#")
            close_index = findnext("#}", source, nextind(source, open_index, 2))
            close_index === nothing && throw(ArgumentError("Unclosed comment tag"))
            cursor = nextind(source, last(close_index))
        elseif startswith(source[open_index:end], "{%")
            close_index = findnext("%}", source, nextind(source, open_index, 2))
            close_index === nothing && throw(ArgumentError("Unclosed statement tag"))
            statement = strip(source[nextind(source, open_index, 2):prevind(source, first(close_index))])

            if statement == "raw"
                raw_close = findnext("{% endraw %}", source, nextind(source, last(close_index)))
                raw_close === nothing && throw(ArgumentError("Unclosed raw block"))
                raw_end = prevind(source, first(raw_close))
                content_start = nextind(source, last(close_index))
                if content_start <= raw_end
                    push!(tokens, (:text, source[content_start:raw_end]))
                else
                    push!(tokens, (:text, ""))
                end
                cursor = nextind(source, last(raw_close))
            else
                push!(tokens, (:stmt, statement))
                cursor = nextind(source, last(close_index))
            end
        else
            push!(tokens, (:text, source[open_index]))
            cursor = nextind(source, open_index)
        end
    end

    if cursor <= lastindex(source)
        push!(tokens, (:text, source[cursor:end]))
    end

    return tokens
end

token_to_source(token::Tuple{Symbol,String}) = token[1] == :text ? token[2] : token[1] == :expr ? "{{ " * token[2] * " }}" : "{% " * token[2] * " %}"

function tokens_to_source(tokens)::String
    return join(token_to_source.(tokens))
end

function preprocess_template(tokens; path::Union{Nothing,String} = nothing, root::Union{Nothing,String} = nothing, overrides::Dict{String,Vector{Tuple{Symbol,String}}} = Dict{String,Vector{Tuple{Symbol,String}}}())
    parent_ref = nothing
    output = Tuple{Symbol,String}[]
    index = 1

    while index <= length(tokens)
        kind, content = tokens[index]

        if kind == :stmt && startswith(content, "extends ")
            parent_ref !== nothing && throw(ArgumentError("Only one extends statement is supported"))
            parent_ref = parse_extends_path(content)
            index += 1
            continue
        elseif kind == :stmt && startswith(content, "block ")
            block_name, block_tokens, next_index = consume_named_block(tokens, index, "block ")
            replacement = get(overrides, block_name, block_tokens)
            append!(output, preprocess_template(replacement; path = path, root = root))
            index = next_index
            continue
        else
            push!(output, tokens[index])
            index += 1
        end
    end

    if parent_ref === nothing
        return output
    end

    path === nothing && throw(ArgumentError("extends requires a file-backed template"))
    child_blocks = collect_named_blocks(tokens)
    parent_path = resolve_relative_template_path(path, parent_ref, root)
    parent_tokens = tokenize(read(parent_path, String))
    return preprocess_template(parent_tokens; path = parent_path, root = root, overrides = child_blocks)
end

function parse_extends_path(statement::String)::String
    path_expr = strip(statement[9:end])
    parsed = Meta.parse(path_expr)
    parsed isa String || throw(ArgumentError("extends expects a string literal path"))
    return parsed
end

function resolve_relative_template_path(current_path::AbstractString, include_path::AbstractString, root::Union{Nothing,String} = nothing)::String
    return resolve_template_path(current_path, include_path; root = root)
end

function collect_named_blocks(tokens)
    blocks = Dict{String,Vector{Tuple{Symbol,String}}}()
    index = 1

    while index <= length(tokens)
        token = tokens[index]
        if token[1] == :stmt && startswith(token[2], "block ")
            block_name, block_tokens, next_index = consume_named_block(tokens, index, "block ")
            blocks[block_name] = block_tokens
            index = next_index
        else
            index += 1
        end
    end

    return blocks
end

function consume_named_block(tokens, start_index::Int, prefix::String)
    statement = tokens[start_index][2]
    name = strip(statement[length(prefix)+1:end])
    stack = String["block"]
    index = start_index + 1
    body = Tuple{Symbol,String}[]

    while index <= length(tokens)
        token = tokens[index]
        if token[1] == :stmt
            stmt = token[2]
            if startswith(stmt, "block ")
                push!(stack, "block")
            elseif startswith(stmt, "if ")
                push!(stack, "if")
            elseif startswith(stmt, "for ")
                push!(stack, "for")
            elseif stmt == "end"
                closing = pop!(stack)
                if isempty(stack)
                    return name, body, index + 1
                elseif closing != "block" || !isempty(stack)
                    push!(body, token)
                end
                index += 1
                continue
            end
        end

        push!(body, token)
        index += 1
    end

    throw(ArgumentError("Unclosed block: " * name))
end

function parse_nodes(tokens, index::Int, stopwords::Set{String}, bindings::Dict{Symbol,Any}, autoescape::Bool)
    statements = Any[]

    while index <= length(tokens)
        kind, content = tokens[index]

        if kind == :stmt
            keyword = first(split(content))
            if content in stopwords || keyword in stopwords
                return statements, index, content
            elseif startswith(content, "for ")
                node, index = parse_for(tokens, index, bindings, autoescape)
                push!(statements, node)
                continue
            elseif startswith(content, "if ")
                node, index = parse_if(tokens, index, bindings, autoescape)
                push!(statements, node)
                continue
            elseif startswith(content, "autoescape ")
                node, index = parse_autoescape(tokens, index, bindings, autoescape)
                push!(statements, node)
                continue
            elseif startswith(content, "set ")
                push!(statements, parse_set(content, bindings))
            elseif startswith(content, "include ")
                push!(statements, parse_include(content, bindings))
            elseif content == "else" || startswith(content, "elseif ") || startswith(content, "elif ") || content == "end"
                throw(ArgumentError("Unexpected template statement: " * content))
            else
                throw(ArgumentError("Unsupported template statement: " * content))
            end
        elseif kind == :expr
            expression = rewrite_expression(parse_template_expression(content), bindings)
            push!(statements, :(write_value!(io, $expression, $autoescape)))
        else
            push!(statements, :(append_text!(io, $(content))))
        end

        index += 1
    end

    return statements, index, nothing
end

function parse_for(tokens, index::Int, bindings::Dict{Symbol,Any}, autoescape::Bool)
    statement = tokens[index][2]
    iterator_source = strip(statement[5:end])
    in_match = match(r"^(.*)\s+in\s+(.*)$"s, iterator_source)
    in_match === nothing && throw(ArgumentError("Invalid for statement: " * statement))

    lhs = Meta.parse(strip(in_match.captures[1]))
    rhs = Meta.parse(strip(in_match.captures[2]))
    loop_bindings = copy(bindings)
    for symbol in binding_symbols(lhs)
        loop_bindings[symbol] = symbol
    end
    loop_bindings[:loop] = :loop
    body, next_index, stopword = parse_nodes(tokens, index + 1, Set(["end"]), loop_bindings, autoescape)
    stopword == "end" || throw(ArgumentError("Unclosed for block"))

    iterator_binding = gensym(:iwai_iter)
    total_binding = gensym(:iwai_total)
    index_binding = gensym(:iwai_index0)
    value_binding = gensym(:iwai_value)

    loop_body = optimize_loop_body(Expr(:block, body...))

    node = quote
        local $iterator_binding = $(rewrite_expression(rhs, bindings))
        local $total_binding = try_length($iterator_binding)
        for ($index_binding, $value_binding) in enumerate($iterator_binding)
            local $(lhs) = $value_binding
            local loop = (
                index = $index_binding,
                index0 = $index_binding - 1,
                first = $index_binding == 1,
                last = $total_binding !== nothing && $index_binding == $total_binding,
                length = $total_binding,
            )
            $loop_body
        end
    end
    return node, next_index + 1
end

function parse_if(tokens, index::Int, bindings::Dict{Symbol,Any}, autoescape::Bool)
    statement = tokens[index][2]
    condition = rewrite_expression(parse_template_expression(statement[4:end]), bindings)
    if_body, next_index, stopword = parse_nodes(tokens, index + 1, Set(["elseif", "elif", "else", "end"]), copy(bindings), autoescape)
    tail, final_index = parse_if_tail(tokens, next_index, stopword, bindings, autoescape)
    node = Expr(:if, condition, Expr(:block, if_body...), tail)
    return node, final_index
end

function parse_if_tail(tokens, index::Int, stopword, bindings::Dict{Symbol,Any}, autoescape::Bool)
    if stopword === nothing
        throw(ArgumentError("Unclosed if block"))
    elseif stopword == "end"
        return nothing, index + 1
    elseif stopword == "else"
        else_body, final_index, else_stop = parse_nodes(tokens, index + 1, Set(["end"]), copy(bindings), autoescape)
        else_stop == "end" || throw(ArgumentError("Unclosed else block"))
        return Expr(:block, else_body...), final_index + 1
    elseif startswith(stopword, "elseif ") || startswith(stopword, "elif ")
        offset = startswith(stopword, "elif ") ? 6 : 8
        condition = rewrite_expression(parse_template_expression(stopword[offset:end]), bindings)
        elseif_body, next_index, elseif_stop = parse_nodes(tokens, index + 1, Set(["elseif", "elif", "else", "end"]), copy(bindings), autoescape)
        tail, final_index = parse_if_tail(tokens, next_index, elseif_stop, bindings, autoescape)
        return Expr(:elseif, condition, Expr(:block, elseif_body...), tail), final_index
    else
        throw(ArgumentError("Unexpected if tail: " * String(stopword)))
    end
end

function parse_autoescape(tokens, index::Int, bindings::Dict{Symbol,Any}, autoescape::Bool)
    statement = tokens[index][2]
    value_source = lowercase(strip(statement[12:end]))
    child_autoescape =
        value_source == "true" ? true :
        value_source == "false" ? false :
        throw(ArgumentError("autoescape expects true or false"))

    body, next_index, stopword = parse_nodes(tokens, index + 1, Set(["end"]), bindings, child_autoescape)
    stopword == "end" || throw(ArgumentError("Unclosed autoescape block"))
    return Expr(:block, body...), next_index + 1
end

function binding_symbols(node)::Set{Symbol}
    result = Set{Symbol}()

    if node isa Symbol
        push!(result, node)
    elseif node isa Expr && node.head == :tuple
        for arg in node.args
            union!(result, binding_symbols(arg))
        end
    end

    return result
end

function rewrite_expression(expr, bindings::Dict{Symbol,Any})
    expr isa Symbol && return rewrite_symbol(expr, bindings)
    expr isa Expr || return expr

    if expr.head == :macrocall
        return expr
    end

    return Expr(expr.head, map(arg -> rewrite_expression(arg, bindings), expr.args)...)
end

function rewrite_symbol(sym::Symbol, bindings::Dict{Symbol,Any})
    haskey(bindings, sym) && return bindings[sym]
    return :(lookup_symbol(ctx, Val($(QuoteNode(sym)))))
end

function parse_set(statement::String, bindings::Dict{Symbol,Any})
    assignment = strip(statement[5:end])
    match_assignment = match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$"s, assignment)
    match_assignment === nothing && throw(ArgumentError("Invalid set statement: " * statement))
    name = Symbol(match_assignment.captures[1])
    value_expr = rewrite_expression(parse_template_expression(match_assignment.captures[2]), bindings)
    local_symbol = get!(bindings, name) do
        gensym(Symbol(:iwai_, name))
    end
    return :(local $local_symbol = $value_expr)
end

function parse_include(statement::String, bindings::Dict{Symbol,Any})
    path_expr = rewrite_expression(parse_template_expression(strip(statement[9:end])), bindings)
    visible_locals = local_pairs_expr(bindings)
    return :(append_text!(io, render_include(__iwai_template__, $path_expr, ctx, $visible_locals)))
end

function parse_template_expression(source::AbstractString)
    stripped = strip(String(source))
    segments = split_filters(stripped)
    expr = Meta.parse(first(segments))

    for segment in segments[2:end]
        expr = build_filter_call(expr, segment)
    end

    return expr
end

function split_filters(source::AbstractString)
    source = String(source)
    parts = String[]
    depth = 0
    start_index = firstindex(source)
    index = firstindex(source)

    while index <= lastindex(source)
        char = source[index]
        if char == '(' || char == '[' || char == '{'
            depth += 1
        elseif char == ')' || char == ']' || char == '}'
            depth -= 1
        elseif char == '|' && depth == 0
            push!(parts, strip(source[start_index:prevind(source, index)]))
            start_index = nextind(source, index)
        end
        index = nextind(source, index)
    end

    push!(parts, strip(source[start_index:end]))
    return parts
end

function build_filter_call(base_expr, filter_segment::String)
    filter_source = strip(filter_segment)
    if occursin('(', filter_source)
        parsed = Meta.parse(filter_source)
        parsed isa Expr && parsed.head == :call || throw(ArgumentError("Invalid filter syntax: " * filter_segment))
        filter_name = parsed.args[1]
        args = map(arg -> arg, parsed.args[2:end])
        return Expr(:call, :apply_filter, Expr(:call, :Val, QuoteNode(filter_name)), base_expr, args...)
    else
        filter_name = Symbol(filter_source)
        return Expr(:call, :apply_filter, Expr(:call, :Val, QuoteNode(filter_name)), base_expr)
    end
end

function optimize_loop_body(body_expr::Expr)::Expr
    body_expr.head == :block || return body_expr
    length(body_expr.args) >= 2 || return body_expr

    first_stmt = body_expr.args[1]
    last_stmt = body_expr.args[end]
    prefix = appended_text(first_stmt)
    suffix = appended_text(last_stmt)

    (prefix === nothing || suffix === nothing || isempty(prefix)) && return body_expr

    optimized_body = copy(body_expr.args)
    optimized_body[1] = :(nothing)
    optimized_body[end] = :(append_text!(io, $(suffix * prefix)))

    return Expr(
        :block,
        :(append_text!(io, $prefix)),
        Expr(:block, optimized_body...),
        :(truncate_suffix!(io, $prefix)),
    )
end

function appended_text(stmt)
    if stmt isa Expr && stmt.head == :call && stmt.args[1] == :append_text! && length(stmt.args) == 3
        value = stmt.args[3]
        value isa String && return value
    end
    return nothing
end

function local_pairs_expr(bindings::Dict{Symbol,Any})
    pairs = Any[]
    for (name, local_symbol) in bindings
        push!(pairs, :($(QuoteNode(name)) => $local_symbol))
    end
    return Expr(:tuple, pairs...)
end
