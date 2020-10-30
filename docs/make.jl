using HorizonSideRobots
using Documenter

makedocs(;
    modules=[HorizonSideRobots],
    authors="Виктор Федоров <fdorov@mail.ru>",
    repo="https://github.com/Arkoniak/HorizonSideRobots.jl/blob/{commit}{path}#L{line}",
    sitename="HorizonSideRobots.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Arkoniak.github.io/HorizonSideRobots.jl",
        assets=String[],
    ),
    pages=[
        "Заглавная" => "index.md",
        "Как установить Робота на своем компьютере" => "setup.md",
        "Конструктор объектов типа Robot" => "constructor.md",
        "Командный интерфейс Робота" => "api.md",
        "Пример выполнения программы для Робота" => "example.md",
        "Начальные сведения о языке программирования Julia" => "language.md"
    ],
)

deploydocs(;
    repo="github.com/Arkoniak/HorizonSideRobots.jl",
)
