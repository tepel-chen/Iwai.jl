pushfirst!(LOAD_PATH, joinpath(@__DIR__, ".."))

using Documenter
using Iwai

makedocs(
    sitename = "Iwai.jl",
    modules = [Iwai],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "Guides" => [
            "Basics" => "guides/basics.md",
            "Inheritance" => "guides/inheritance.md",
            "Security" => "guides/security.md",
        ],
        "API" => "api.md",
    ],
)

deploydocs(repo = "github.com/tepel-chen/Iwai.jl.git")
