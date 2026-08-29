using HorizonSideRobots
using Documenter

makedocs(;
    modules=[HorizonSideRobots],
    authors="Виктор Федоров <fdorov@mail.ru>",
    repo="https://github.com/Vibof/HorizonSideRobots.jl/blob/{commit}{path}#L{line}",
    sitename="HorizonSideRobots.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Vibof.github.io/HorizonSideRobots.jl",
        assets=String[],
    ),

    pages=[
    "Заглавная" => "index.md",
    "Установка и начало работы" => "setup.md",
    "Пример разработки программного кода" => "source_mark_kross.md",
    ],
)

deploydocs(;
    repo="github.com/Vibof/HorizonSideRobots.jl",
)
