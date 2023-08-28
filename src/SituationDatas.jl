# Вспомогательный модуль, определяющий структуру данных для представления обстановки на поле и функции для работы с этими данными 
# Он используется как модуль, вложенный в модуль HorizonSideRobots

module SituationDatas
    using GLMakie, ...HorizonSideRobots #: HorizonSide
    export SituationData, draw, save, adjacent_position, is_inner_border, is_inside, sitedit!, handle_button_press_event!

    const BORDER_COLOR = :blue
    const BORDER_WIDTH = 3
    
    const BODY_CROSS_LENGTH = 0.5 # концы креста чуть-чуть выступают за пределы тела робота, но часть креста в пределах тела нейтрализована
    const BODY_CROSS_THICKNESS = 2
    const BODY_CROSS_COLOR = :darkgray
    const BODY_SIZE = 1 # размеры тела робота подобраны для поля 11x12 (важен только наибольший из 2х размеров)  
    const BODY_COLOR = :gray 
    const BODY_ALPHA = 0.5 # тело робота делается полупрозрачным с тем, чтобы сквозь него могли бы просвечивать маркеры
    const BODY_STYLE = :o
    
    const MARKER_SIZE = 0.8
    const MARKER_COLOR = :red 
    const MARKER_STYLE = :rect

    const DELTA_AXIS_SIZE = 0.03 # - "запас" для рамки axis, чтобы при установке внешней рамки поля она была бы хорошо видна 

    mutable struct SituationData
        frame_size::Tuple{UInt,UInt} # = (число_строк_поля, число_столбцов_поля)
        coefficient::Float64
        is_framed::Bool # = true, если имеется внешняя рамка
        robot_position::Tuple{Int,Int} # - пара: номер строки, номер столбца (как в матрице, но возможны и неположительные значения)
        temperature_map::Matrix{Int} # считается, что за пределами фрейма температура всюду равна 0
        markers_map::Set{Tuple{Int,Int}} # содержит позиции клеток поля, в которых находятся маркеры 
        borders_map::Matrix{Set{HorizonSide}} # - матрица множеств запрещенных направлений: каждый ее элемент соответствует некоторой клетке поля (только в его видимой части) и содержит множество направлениями (::HorizonSide), в которых имеются перегородки (внешняя рамка, даже если она есть, здесь в расчет не берется)
        SituationData(frame_size::Tuple{Integer,Integer}) = new(init_default(frame_size)...)       
        SituationData(file_name::AbstractString) =  new(load(file_name)...)
        fig::Union{Tuple{Figure, Axis}, Nothing}
    end

    #body_create(coefficient::AbstractFloat,x::AbstractFloat,y::AbstractFloat; body_color=BODY_COLOR) = scatter([x],[y], c=body_color, s=BODY_SIZE*coefficient, marker=BODY_STYLE, alpha=BODY_ALPHA) 
    function body_create(x::AbstractFloat, y::AbstractFloat, color=BODY_COLOR)
        for posf ∈  [(l -> ([x - l, x + l], [y])), (l -> ([x], [y - l, y + l]))]
            r = (length, color) -> lines!(posf(length)..., color=color, linewidth=BODY_CROSS_THICKNESS)
            r(BODY_CROSS_LENGTH, BODY_CROSS_COLOR)
            r(BODY_SIZE/2-0.1, :white)
        end
        scatter!(x, y, marker=:circle, markerspace=:data, markersize=BODY_SIZE, color=(BODY_COLOR, BODY_ALPHA))
    end

    function draw(sit::SituationData)
        # иницицализируем окно
        if sit.fig === nothing
            fig = Figure()
            axis = Axis(fig[1,1],
                limits = ((1, sit.frame_size[2]+1), (1, sit.frame_size[1]+1)),
                xticks = (1:1:sit.frame_size[2]+1),
                yticks = (1:1:sit.frame_size[1]+1),
                xticksvisible = false,
                yticksvisible = false,
                xticklabelsvisible = false,
                yticklabelsvisible = false,
                xzoomlock = true,
                yzoomlock = true,
                xrectzoom = false,
                yrectzoom = false,
                aspect = 1,
            )
            sit.fig = (fig, axis)
        else
            empty!(sit.fig[2])
        end
        sit.fig[2].leftspinevisible = sit.is_framed
        sit.fig[2].topspinevisible = sit.is_framed
        sit.fig[2].rightspinevisible = sit.is_framed
        sit.fig[2].bottomspinevisible = sit.is_framed

        get_coordinates(position::Tuple{Integer,Integer}) = (position[2]+1, sit.frame_size[1]-position[1]+1)

        # отрисовка внутренних границы
        begin
            # Предполагается, что сторона каждой клетки поля равна 1
            # клетки на границе поля НЕ исключаются из рассмотрения, т.к. возможны перегородки, "уходящие в бескнечность"              
            for i ∈ 1:sit.frame_size[1], j ∈ 1:sit.frame_size[2]
                x, y = get_coordinates((i, j))
                r = (x, y) -> lines!(x, y, color=BORDER_COLOR, linewidth=BORDER_WIDTH)
                for side ∈ sit.borders_map[i,j]
                    if side==Nord
                        r([x-1, x], [y+1])
                    elseif side==West
                        r([x-1], [y, y+1])
                    elseif side==Sud
                        r([x-1, x], [y])
                    else
                        r([x], [y, y+1])
                    end
                end
            end
        end # тут, как и положено, все перегородки рисуются ТОЛЬКО ПО ОДНОМУ РАЗУ !!!

        function get_coordinates_center(pos::Tuple{Integer,Integer}) :: Tuple{AbstractFloat, AbstractFloat}
            x, y = get_coordinates(pos)
            (x - 0.5, y + 0.5)
        end

        scatter!(map(get_coordinates_center, collect(sit.markers_map)), color=MARKER_COLOR, markerspace=:data, markersize=MARKER_SIZE, marker=MARKER_STYLE)

        # отрисовка робота
        if is_inside(sit) # робот - в пределах поля (иная ситуация может возникнуть при перемещениях робота)
            x, y = get_coordinates_center(sit.robot_position)

            body_create(x, y)
        end

        display(sit.fig[1])
    end # function draw

    is_inside(position::Tuple{Integer,Integer},frame_size::Tuple{UInt,UInt})::Bool = (0 < position[1] <= frame_size[1]) && (0 < position[2] <= frame_size[2])

    is_inside(sit::SituationData)::Bool = is_inside(sit.robot_position, sit.frame_size)

    function init_default(frame_size::Tuple{Integer,Integer})
        robot_position = (frame_size[1], 1) # по умолчанию начальное положение - левый нижний угол (Sud-West)
        is_framed = true # - по умолчанию имеется внешняя ограждающая поле рамка
        temperature_map = rand(-273:500, frame_size...)
        markers_map = Set{Tuple{Int,Int}}() # - пустое множество, т.е. по умолчанию маркеров на поле нет
        borders_map = fill(Set(), frame_size) # - матрица пустых множеств, т.е. по умолчанию на поле внутренних перегородок нет
        coefficient = 12/max(frame_size...) # - для размеров поля 11x12 coefficient = 1.0
        fig = nothing
        return frame_size, coefficient, is_framed, robot_position, temperature_map, markers_map, borders_map, fig
    end

    function load(file_name::AbstractString) 
        io = open(file_name)
        readline(io) # -> "frame_size:"
        frame_size = Tuple(parse.(Int, split(readline(io))))
        readline(io) # -> coefficient
        coefficient = parse(Float64,readline(io))
        readline(io) # -> "is_framed:"
        is_framed = (parse(Bool, readline(io)))
        readline(io) # -> "robot_position:"
        robot_position = Tuple(parse.(Int, split(readline(io))))
        readline(io) # -> "temperature_map:"     
        temperature_map = reshape(parse.(Int, split(readline(io))), frame_size)
        readline(io) # -> "markers_map:"
        line = strip(readline(io))
        if isempty(line) == true
            markers_map = Set()
        else
            markers_map = Set(Tuple(parse.(Int,split(index_pair, ","))) for index_pair in split(line[2:end-1], ")("))   
        end
        readline(io) # -> "borders_map:"
        borders_map = fill(Set(), prod(frame_size)) # - вектор пустых множеств
        for k ∈ eachindex(borders_map) 
            line = strip(readline(io))
            isempty(line) || (borders_map[k] = Set(HorizonSide.(parse.(Int, split(line)))))
        end
        borders_map = reshape(borders_map, frame_size) 
        return frame_size, coefficient, is_framed, robot_position, temperature_map, markers_map, borders_map, nothing
    end # nested funcion load

    function save(sit::SituationData,file_name::AbstractString)
        open(file_name,"w") do io
            write(io, "frame_size:\n") # 11 12
            write(io, join(sit.frame_size, " "),"\n")
            write(io, "coefficient:\n")
            write(io, join(sit.coefficient),"\n")
            write(io, "is_framed:\n") # "true"
            write(io, join(sit.is_framed), "\n")
            write(io, "robot_position:\n") # 1 1
            write(io, join(sit.robot_position, " "), "\n")
            write(io, "temperature_map:\n") # 1 2 3 1 2
            write(io, join(sit.temperature_map, " "), "\n")
            write(io, "markers_map:\n") # "(1, 2)(3, 2)(4, 5)"
            write(io, join(sit.markers_map), "\n")
            write(io,"borders_map:\n")
            for set_positions ∈ sit.borders_map # set_positions - множество запрещенных направлений
                write(io, join(Int.(set_positions)," "), "\n")   # 0 1 3
            end
        end 
    end # nested function save

    function adjacent_position(position::Tuple{Integer,Integer},side::HorizonSide)
    # - возвращает соседнюю позицию (в пределах фрейма) с заданного направления
        if side == Nord
            return position[1]-1, position[2]
        elseif side == Sud
            return position[1]+1, position[2]
        elseif side == Ost
            return position[1], position[2]+1
        elseif side == West
            return position[1], position[2]-1
        end
    end  
        
    function is_inner_border(position::Tuple{Integer,Integer}, side::HorizonSide, borders_map::Matrix{Set{HorizonSide}})
    # - проверяет наличие перегородки и дополнительно возвращает актуальную позицию и направление на перегородку (если перегородка есть)
    # (в матрице borders_map каждому элементу соответствует "актуальная" позиция: из 2х соседних позиций только одна может быть "актуальной")
        if side ∈ borders_map[position...]
            return true, position, side
        else
            position = adjacent_position(position,side) # - соседняя позиция в первоначальном направленн
            side = HorizonSide(mod(Int(side)+2, 4)) # - противоположное направление, относительно первоначального
            if is_inside(position,Tuple{UInt,UInt}(size(borders_map))) && side ∈ borders_map[position...]
                return true, position, side
            else
                return false, nothing, nothing
            end
        end
    end

    function handle_button_press_event!(event, sit, file::AbstractString, is_fixed)
        # Обработчик события "button_press_event" (клик мышью по figure)
        # При кликании в пределах axes,
        # в зависимости от значения координат курсора мыши в пределах одной их клеток, в зависимомти от того, 
        # находится ли в данной клетке робот, и в зависимости от того, был ли предыдущий клик по клетке с роботом, 
        # ставится либо маркер, либо ставится/снимается перегородка, либо робот перемещается на новую позиции. Причем
        # ограничивающая поле (фрейм) перегородка ставится/снимается за один клик, все остальные перегородки состоят
        # из отрезков (сторон клеток), которые ставятся/снимаются только индивидуально.
        # Клик за пределами axes пока что игнорируется (планируется, что когда-нибудь такие клики будут приводить к соответствующим изменениям размеров поля).
        # Результат каждого акта редактирования обстановки немедленно сохраняется в файле file

        if event.action != Mouse.press
            return
        end
 
        x, y = mouseposition(sit.fig[2]) # - координаты относительно лев.нижн.угла поля
        # сторона клетки равна 1
        if x < 0.5 || y < 0.5 || x > sit.frame_size[2]+1.5 || y > sit.frame_size[1]+1.5 # <=> клик за пределами axes
            return
        end

        position = Int.((sit.frame_size[1]-floor(y)+1, floor(x))) # - позиция клика
        Δx, Δy = x-floor(x)-0.5, y-floor(y)-0.5 # - координаты относительно ЦЕНТРА текущей клетки 
        ρ = 0.25 # - величина ("радиус") "внутренности" клетки
        δ = 0.5-ρ # - величина "окрестности" границы
        x_max, y_max = reverse(sit.frame_size)
    
        if abs(Δy) > ρ || abs(Δx) > ρ # клик - по границе между клетками (или в окрестности внешней рамки)
            if is_fixed.x == true
                # пока робот не поставлен в новую позицию, редактировать перегородки не возможно
                return
            end
        end

        function set_or_del_border!(position,side::HorizonSide) 
        # - ставит/удаляет перегородку в текущей позиции на заданном направлении
            required_pop, actual_position, actual_side = is_inner_border(position, side, sit.borders_map)
            if required_pop == true # в sit.borders_map надо "удалить" перегородку из позиции actual_position в направлении actual_side 
                pop!(sit.borders_map[actual_position...],actual_side) # (actual_side == side | inverse(side))
            else # в sit.borders_map надо поставить перегородку на Севере
                push!(sit.borders_map[position...],side)
            end
        end

        function set_or_del_marker!(position) 
        # - ставит/удаляет маркер в текущей позиции
            if position ∈ sit.markers_map
                pop!(sit.markers_map, position) # маркер удален
            else
                push!(sit.markers_map, position) # маркер поставлен
            end
        end

        if x-1 < δ || y-1 < δ || x_max+1-x < δ || y_max+1-y < δ # -  клик - в окрестности рамки
            sit.is_framed = !(sit.is_framed)
        elseif Δy >= abs(Δx) && Δy >= ρ   
            set_or_del_border!(position,Nord)
        elseif Δx <= -abs(Δy) && Δx <= -ρ 
            set_or_del_border!(position,West)
        elseif Δy <= -abs(Δx) && Δy <= -ρ 
            set_or_del_border!(position,Sud)
        elseif Δx >= abs(Δy) && Δx >= ρ   
            set_or_del_border!(position,Ost)
        else # set_or_del_marker! ИЛИ фикировать текущее положение робота ИЛИ переместить зафиксированного робота в новое положение
            if sit.robot_position == position 
                if is_fixed.x == false                   
                    is_fixed.x = true
                    body_create(floor(x)+0.5,floor(y)+0.5, :white)
                    # цвет робота временно стал белым (положение робота "фиксировано")
                    return # draw(...) не выполняется
                else  
                    is_fixed.x = false # после выполнения draw(...) робот останется на прежнем месте
                end
            else # в текущей клетке (по которой был клик) робота нет
                if is_fixed.x == false # до этого по клетке с роботом клика не было
                    set_or_del_marker!(position) 
                else
                    is_fixed.x = false
                    sit.robot_position = position # робот поставлен в текущую позицию
                end 
            end
        end
        save(sit, file)
        draw(sit)
    end # function handle_button_press_event!
    
    function sitedit!(sit::SituationData, file::AbstractString)
    # - открывает обстановку, соответствующей структуре данных sit, в НОВОМ окне
    # - обеспечивает возможность редактирования обстановки с помощью мыши
    # - результат сохраняет в 2-х форматах: в файле file (sit-файл) и в файле file*".png" (в формате png)
        sit.fig = nothing
        draw(sit)

        is_fixed = Ref(false)
        on(event -> handle_button_press_event!(event, sit, file, is_fixed), events(sit.fig[2]).mousebutton)
        return nothing
    end
end # module SituationDatas
