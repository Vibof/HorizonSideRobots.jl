# HorizonSideRobots.jl

# DATE: 2020 09 12 15-03

module HorizonSideRobots # "робот на клетчатом поле со сторонами горизонта"

export HorizonSide, Nord, Sud, West, Ost, Robot, move!, isborder, putmarker!, ismarker, temperature, show, show!, save, sitedit, sitcreate

"""
    @enum HorizonSide Nord=0 West=1 Sud=2 Ost=3

-- Определяет стороны горизонта на клетчатом поле с роботом: Nord - Север (вверху), West - Запад (слева), Sud - Юг (внизу), Ost - Восток (справа)     
"""
@enum HorizonSide Nord=0 West=1 Sud=2 Ost=3

ANIMATION_SLEEP_TIME=0.01 

module SituationData
    using PyPlot, ...HorizonSideRobots #: HorizonSide
    export Situation, draw, save, adjacent_position, is_inner_border, is_inside, sitedit!, handle_button_press_event!, Figure, gcf

    BUFF_SITUATION = nothing # инициализируется в draw(...), а затем используется в в handle_button_press_event!(...)
    IS_FIXED_ROBOT_POSITION = false # используется как флаг в handle_button_press_event!(...)
    
    const BORDER_COLOR = :blue
    const BORDER_WIDTH = 3
    
    const BODY_KREST_SIZE = 1200 # концы креста чуть-чуть выступают за пределы тела робота, но часть креста в пределах тела нейтрализована
    const BODY_SIZE = 800 # размеры тела робота подобраны для поля 11x12 (важен только наибольший из 2х размеров)  
    const BODY_COLOR = :gray 
    const BODY_ALPHA = 0.5 # тело робота делается полупрозрачным с тем, чтобы сквозь него могли бы просвечивать маркеры
    const BODY_STYLE = :o
    
    const MARKER_SIZE = 150 #250
    const MARKER_COLOR = :red 
    const MARKER_STYLE = :s 

    const DELTA_AXIS_SIZE = 0.03 # - "запас" для рамки axis, чтобы при установке внешней рамки поля она была бы хорошо видна 

    mutable struct Situation
        frame_size::Tuple{UInt,UInt} # = (число_строк_поля, число_столбцов_поля)
        coefficient::Float64
        is_framed::Bool # = true, если имеется внешняя рамка
        robot_position::Tuple{Int,Int} # - пара: номер строки, номер столбца (как в матрице, но возможны и неположительные значения)
        temperature_map::Matrix{Int} # считается, что за пределами фрейма температура всюду равна 0
        markers_map::Set{Tuple{Int,Int}} # содержит позиции клеток поля, в которых находятся маркеры 
        borders_map::Matrix{Set{HorizonSide}} # - матрица множеств запрещенных направлений: каждый ее элемент соответствует некоторой клетке поля (только в его видимой части) и содержит множество направлениями (::HorizonSide), в которых имеются перегородки (внешняя рамка, даже если она есть, здесь в расчет не берется)
        Situation(frame_size::Tuple{Integer,Integer}) = new(init_default(frame_size)...)       
        Situation(file_name::AbstractString) =  new(load(file_name)...)
    end

    body_create(coefficient::AbstractFloat,x::AbstractFloat,y::AbstractFloat; body_color=BODY_COLOR) = scatter([x],[y], c=body_color, s=BODY_SIZE*coefficient, marker=BODY_STYLE, alpha=BODY_ALPHA) 

    function draw(sit::Situation; newfig::Bool=true) #, file::AbstractString="temp.sit")
    # -- отображает обстановку (sit) в новом окне (newfig==true)) или - в текущем (newfig=false; но если окно отсутствовало, то оно создается)
    # Если newfig==true, то окно с прежней обстановкой сохраняется, это может быть полезно при отладке, чтобы увидеть результаты сразу в нескольких точках кода 
    # -- Инициализирует global BUFF_SITUATION, которая получает структуру данных (::Situation), определяющую текущую обстановку   
        global BUFF_SITUATION 
        BUFF_SITUATION = sit
        
        function robot_create(x::AbstractFloat,y::AbstractFloat)
            scatter([x],[y], c=:k, s=BODY_KREST_SIZE*sit.coefficient, marker=:+, alpha=1) 
            scatter([x],[y], c=:w, s=BODY_SIZE*sit.coefficient, marker=:+, alpha=1) # нейтрализует крест в пределах тела
            body_create(sit.coefficient,x,y) # тело - полупрозрачное
        end
        
        marker_create(coefficient::AbstractFloat,x::AbstractFloat,y::AbstractFloat) = scatter([x],[y],c=MARKER_COLOR,s=MARKER_SIZE*coefficient,marker=MARKER_STYLE)
        
        function field_create(axes_size::Tuple{UInt,UInt}, newfig::Bool) 
        # -- создает пустое поле заданных размеров, разделенное на клетки размером 1х1 каждая
            rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
            rcParams["toolbar"]="None" # - строки toolbar в figure быть не должно
            rcParams["axes.edgecolor"]=rcParams["figure.facecolor"] # - рамка осей должен не должна быть видимой
            rcParams["xtick.color"]=rcParams["figure.facecolor"] # - разметка осей не должна быть видимой
            rcParams["ytick.color"]=rcParams["figure.facecolor"] 
            rcParams["figure.figsize"]=(7*axes_size[1]/axes_size[2],7-0.2) # - размеры окна задаются с учетом отсутствия toolbar и сучетом фактических размеров клеточного поля (если бы имелся toolbar, то по умолчанию размеры canvas были бы - 7*7 дюймов)
            if newfig==true
                figure() # - создается новое окно (пока без координатных осей)
            else
                cla() # - очищаются текущие координатные оси (если их не было, то автоматически создаются новые в новом окне)
            end
            axis([-DELTA_AXIS_SIZE, axes_size[1]+DELTA_AXIS_SIZE, -DELTA_AXIS_SIZE, axes_size[2]+DELTA_AXIS_SIZE]) # - устанавливаются размеры текущих осей или создаются новые оси в текущем окне
            xticks(0:axes_size[1]) # - задаются положения координатных линий
            yticks(0:axes_size[2])
            grid(true) # - отображаются координатные линии
            return nothing
        end # nested function field_create    

        get_coordinates(position::Tuple{Integer,Integer})=(position[2]-0.5, sit.frame_size[1]-position[1]+0.5)        

        function internal_borders_create(num_rows,num_colons)
            # Предполагается, что сторона каждой клетки поля равна 1              
            for i ∈ 1:num_rows, j ∈ 1:num_colons # клетки на границе поля НЕ исключаются из рассмотрения, т.к. возможны перегородки, "уходящие в бескнечность"
                x,y = get_coordinates((i,j))
                for side ∈ sit.borders_map[i,j]
                    # (x,y) - координаты центра (i,j)-клетки, 
                    # в направлении side, от которой должна быть поставлена перегородка 
                    if side==Nord
                        x1,y1 = x+0.5,y+0.5 
                        x2,y2 = x-0.5,y+0.5 
                    elseif side==West
                        x1,y1 = x-0.5,y+0.5 
                        x2,y2 = x-0.5,y-0.5
                    elseif side==Sud
                        x1,y1 = x-0.5,y-0.5 
                        x2,y2 = x+0.5,y-0.5 
                    else # if side==Ost
                        x1,y1 = x+0.5,y-0.5 
                        x2,y2 = x+0.5,y+0.5 
                    end
                    plot([x1,x2], [y1,y2], linewidth=BORDER_WIDTH, color=BORDER_COLOR)
                end
            end # тут, как и положено, все перегородки рисуются ТОЛЬКО ПО ОДНОМУ РАЗУ !!!
        end # nested function internal_borders_create

        ion() # - без этого в среде Pluto нельзя редактировать обстановку 
        field_create(reverse(sit.frame_size), newfig)
        internal_borders_create(sit.frame_size...)
        if sit.is_framed == true
            plot([0,sit.frame_size[2],sit.frame_size[2],0,0], [0,0,sit.frame_size[1],sit.frame_size[1],0], linewidth=BORDER_WIDTH, color=BORDER_COLOR)
        end
        for position ∈ sit.markers_map
            marker_create(sit.coefficient,get_coordinates(position)...)
        end
        if is_inside(sit)==true # робот - в пределах поля (иная ситуация может возникнуть при перемещениях робота)
            robot_create(get_coordinates(sit.robot_position)...)            
        end
        show() # - без этого в среде Pluto не открвыается окно с роботом
        return nothing 
    end # function draw

    is_inside(position::Tuple{Integer,Integer},frame_size::Tuple{UInt,UInt})::Bool = (0 < position[1] <= frame_size[1]) && (0 < position[2] <= frame_size[2])

    is_inside(sit::Situation)::Bool = is_inside(sit.robot_position, sit.frame_size)

    function init_default(frame_size::Tuple{Integer,Integer})
        robot_position = (frame_size[1], 1) # по умолчанию начальное положение - левый нижний угол (Sud-West)
        is_framed = true # - по умолчанию имеется внешняя ограждающая поле рамка
        temperature_map = rand(-273:500, frame_size...)
        markers_map = Set{Tuple{Int,Int}}() # - пустое множество, т.е. по умолчанию маркеров на поле нет
        borders_map = fill(Set(), frame_size) # - матрица пустых множеств, т.е. по умолчанию на поле внутренних перегородок нет
        coefficient = 12/max(frame_size...) # - для размеров поля 11x12 coefficient = 1.0
        return frame_size, coefficient, is_framed, robot_position, temperature_map, markers_map, borders_map
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
        return frame_size, coefficient, is_framed, robot_position, temperature_map, markers_map, borders_map
    end # nested funcion load

    function save(sit::Situation,file_name::AbstractString)
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

    function handle_button_press_event!(event, file::AbstractString)
        # Обработчик события "button_press_event" (клик мышью по figure)
        # При кликании в пределах axes,
        # в зависимости от значения координат курсора мыши в пределах одной их клеток, в зависимомти от того, 
        # находится ли в данной клетке робот, и в зависимости от того, был ли предыдущий клик по клетке с роботом, 
        # ставится либо маркер, либо ставится/снимается перегородка, либо робот перемещается на новую позиции. Причем
        # ограничивающая поле (фрейм) перегородка ставится/снимается за один клик, все остальные перегородки состоят
        # из отрезков (сторон клеток), которые ставятся/снимаются только индивидуально.
        # Клик за пределами axes пока что игнорируется (планируется, что когда-нибудь такие клики будут приводить к соответствующим изменениям размеров поля).
        # Результат каждого акта редактирования обстановки немедленно сохраняется в файле file
 
        global BUFF_SITUATION, IS_FIXED_ROBOT_POSITION
  
        # x, y = event.x, event.y - координаты в пределах всего холста (в пикселах)
        x, y = event.xdata, event.ydata # - координаты относительно лев.нижн.угла поля
        # сторона клетки равна 1
        if x ≡ nothing  # <=> клик за пределами axes
            return nothing
        end

        position = Int.((BUFF_SITUATION.frame_size[1]-floor(y), ceil(x))) # - позиция клика
        Δx, Δy = x-floor(x)-0.5, y-floor(y)-0.5 # - координаты относительно ЦЕНТРА текущей клетки 
        ρ = 0.25 # - величина ("радиус") "внутренности" клетки
        δ = 0.5-ρ # - величина "окрестности" границы
        x_max, y_max = reverse(BUFF_SITUATION.frame_size)
    
        if abs(Δy) > ρ || abs(Δx) > ρ # клик - по границе между клетками (или в окрестности внешней рамки)
            if IS_FIXED_ROBOT_POSITION == true
                # пока робот не поставлен в новую позицию, редактировать перегородки не возможно
                return nothing
            end
        end

        function set_or_del_border!(position,side::HorizonSide) 
        # - ставит/удаляет перегородку в текущей позиции на заданном направлении
            required_pop, actual_position, actual_side = is_inner_border(position, side, BUFF_SITUATION.borders_map)
            if required_pop == true # в BUFF_SITUATION.borders_map надо "удалить" перегородку из позиции actual_position в направлении actual_side 
                pop!(BUFF_SITUATION.borders_map[actual_position...],actual_side) # (actual_side == side | inverse(side))
            else # в BUFF_SITUATION.borders_map надо поставить перегородку на Севере
                push!(BUFF_SITUATION.borders_map[position...],side)
            end
        end

        function set_or_del_marker!(position) 
        # - ставит/удаляет маркер в текущей позиции
            if position ∈ BUFF_SITUATION.markers_map
                pop!(BUFF_SITUATION.markers_map, position) # маркер удален
            else
                push!(BUFF_SITUATION.markers_map, position) # маркер поставлен
            end
        end

        if x < δ || y < δ || x_max-x < δ || y_max-y < δ # -  клик - в окрестности рамки
            BUFF_SITUATION.is_framed = !(BUFF_SITUATION.is_framed)
        elseif Δy >= abs(Δx) && Δy >= ρ   
            set_or_del_border!(position,Nord)
        elseif Δx <= -abs(Δy) && Δx <= -ρ 
            set_or_del_border!(position,West)
        elseif Δy <= -abs(Δx) && Δy <= -ρ 
            set_or_del_border!(position,Sud)
        elseif Δx >= abs(Δy) && Δx >= ρ   
            set_or_del_border!(position,Ost)
        else # set_or_del_marker! ИЛИ фикировать текущее положение робота ИЛИ переместить зафиксированного робота в новое положение
            if BUFF_SITUATION.robot_position == position 
                if IS_FIXED_ROBOT_POSITION == false                   
                    IS_FIXED_ROBOT_POSITION = true
                    body_create(BUFF_SITUATION.coefficient, floor(x)+0.5,floor(y)+0.5; body_color=:white)
                    # цвет робота временно стал белым (положение робота "фиксировано")
                    return nothing # draw(...) не выполняется                     
                else  
                    IS_FIXED_ROBOT_POSITION = false # после выполнения draw(...) робот останется на прежнем месте
                end
            else # в текущей клетке (по которой был клик) робота нет
                if IS_FIXED_ROBOT_POSITION == false # до этого по клетке с роботом клика не было
                    set_or_del_marker!(position) 
                else
                    IS_FIXED_ROBOT_POSITION = false
                    BUFF_SITUATION.robot_position = position # робот поставлен в текущую позицию
                end 
            end
        end
        draw(BUFF_SITUATION; newfig=false)
        # Изменения должны отображаться в тех же самых координатных осях, где они и были произведены, поэтому обязательно должно быть 
        # newfig==false
        save(BUFF_SITUATION, file)
        savefig(file*".png";format="png") #, facecolor=rcParams["figure.facecolor"], edgecolor=’w’, orientation=’portrait’, papertype=None, transparent=False, bbox_inches=None, pad_inches=0.1)
    end # function handle_button_press_event!
    

    function sitedit!(sit::Situation, file::AbstractString)
    # - открывает обстановку, соответствующей структуре данных sit, в НОВОМ окне
    # - обеспечивает возможность редактирования обстановки с помощью мыши
    # - результат сохраняет в файле file 
    # - одновременно с этим обстановка сохраняется в файле "situation.png" (в формате png)
        global BUFF_SITUATION, IS_FIXED_ROBOT_POSITION
        BUFF_SITUATION=sit
        draw(BUFF_SITUATION; newfig=true)
        gcf().canvas.mpl_connect("button_press_event", event -> handle_button_press_event!(event, file))
        gcf().canvas.mpl_connect("close_event", event -> begin global BUFF_SITUATION, IS_FIXED_ROBOT_POSITION; BUFF_SITUATION, IS_FIXED_ROBOT_POSITION = nothing, false end)
        return nothing
    end

end # module SituationData-------------------------------------------------------

using .SituationData

"""
    r = Robot(;animate=false) 

    r = Robot(num_rows::Integer, num_colons::Integer; animate=false)
    
    r = Robot(file_name::AbstractString; animate=false)

-- Конструктор объектов типа Robot (исполнитель "Робот на клетчатом поле со сторонами горизонта типа HorizonSide"):

.    - в первом случае - пустое ограниченное поле будет иметь размер 11х12 и робот будет - в левом нижнем углу

.    - во втором случае - поле будет иметь указанные размеры

.    - в третьем случае - обстановка загружается из указанного файла

-- Если animate=true, то при этом открывается окно с соответствующей начальной обстановкой 
(которую можно будет редактировать, и результат редактирования будет сохраняться в файлах "untitled.sit", "situation.png"). 
Иначе просто создается объект, соодержащий данные, определяющие эту обстановку (визуализации обстановки в этом случае нет).

Командный интерфейс исполнителя (объекта) типа Robot: `move!`, `isboarder`, `putmarker`, `ismarker`, `temperature`, `show`, `show!` (см. help)

Для подготовительной работы с sit-файлами (в этих файлах сохраняется данные с информацией о некоторой обстановке на поле с роботом) 
имеются специальные функции: `show!`, `sitedit`, `sitcreate` (см. help)

"""
mutable struct Robot
    situation::Situation
    animate::Bool # если true, то - имеет место непрерывная визуализация смены обстановки при выполнении команд робота
    actualfigure::Union{Nothing,Figure}
    Robot(sit::Situation;animate=false) = begin 
        if animate==true 
            sitedit!(sit, "untitled.sit")  
        end 
        new(sit,animate,nothing) 
    end
    Robot(frame_size::Tuple{Integer,Integer}=(UInt(11),UInt(12));animate=false) = Robot(Situation(frame_size),animate=animate) 
    Robot(num_rows::Integer,num_colons::Integer;animate=false) = Robot((num_rows,num_colons);animate=animate) 
    Robot(file_name::AbstractString;animate=false) = Robot(Situation(file_name);animate=animate) 
end

"""
    move!(r::Robot, side::HorizonSide)::Nothing

-- Перемещает робота в соседнюю клетку в заданном направлении (если только на пути нет перегoродки, в противном случае - прерывание)
"""
function move!(r::Robot, side::HorizonSideRobots.HorizonSide)
    if isborder(r,side)==true   
        error("Робот врезался в перегородку при попытке сделать шаг в направлении $(side)") 
    end
    r.situation.robot_position = adjacent_position(r.situation.robot_position, side)
    if r.animate==true 
        draw(r.situation; newfig=false) 
        sleep(ANIMATION_SLEEP_TIME)
    end
    return nothing
end

"""
    isborder(r::Robot, side::HorizonSide)::Bool

-- Проверяет наличие перегородки в заданном направлении
"""
function isborder(r::Robot,side::HorizonSideRobots.HorizonSide)::Bool
    i,j = position(r)
    imax,jmax = r.situation.frame_size
    if (i<1 && j<1)||(i<1 && j>jmax)||(i>imax && j>jmax)||(i>imax && j<1) # - (i,j) - за пределами фрейма (в угловых секторах)
        return false # ни в каких направлениях перепятствий быть не может (т.к. на периметре фрейма не может быть перегородок, отличных от сплошной рамки)                
    elseif i<1 && 1<=j<=jmax # - (i,j) - за пределами фрейма (в северном секторе)
        if side ∈ (Nord,Sud)
            return false # в этих двух направлениях перепятствий быть не может (т.к. на периметре фрейма не может быть перегородок, отличных от сплошной рамки) 
        end
        return side ∈ r.situation.borders_map[1,j] # i=1
    elseif 1<=i<=imax && j>jmax # - (i,j) - за пределами фрейма (в восточном секторе)
        if side ∈ (Ost,West)
            return false # в этих двух направлениях перепятствий быть не может (т.к. на периметре фрейма не может быть перегородок, отличных от сплошной рамки) 
        end   
        return side ∈ r.situation.borders_map[i,jmax] # j=jmax       
    elseif i>imax && 1<=j<=jmax # - (i,j) - за пределами фрейма (в южном секторе)
        if side ∈ (Nord,Sud)
            return false # в этих двух направлениях перепятствий быть не может (т.к. на периметре фрейма не может быть перегородок, отличных от сплошной рамки) 
        end      
        return side ∈ r.situation.borders_map[imax,j] # i=imax
    elseif 1<=i<=imax && j<1 # - (i,j) - за пределами фрейма (в западном секторе)
        if side ∈ (Ost,West)
            return false # в этих двух направлениях перепятствий быть не может (т.к. на периметре фрейма не может быть перегородок, отличных от сплошной рамки)            
        end      
        return side ∈ r.situation.borders_map[i,1] # j=1
    else # - (i,j) - в пределах фрейма (is_inside(r) == true)
        if r.situation.is_framed == true
            if side==Nord && i==1 || side==Sud && i==imax || side==West && j==1 || side==Ost && j==jmax
                return true # - робот рядом с внешней рамкой и направление - в сторону рамку
            end
        end 
        return is_inner_border(r.situation.robot_position, side, r.situation.borders_map)[1] # side ∈ r.situation.borders_map[i,j]
    end
end # function isborder

"""
    putmarker!(r::Robot)::Nothing

-- Ставит маркер в клетке с роботом
"""
putmarker!(r::Robot)::Nothing = begin 
    push!(r.situation.markers_map, position(r))
    if r.animate == true 
        draw(r.situation;newfig=false) 
    end
    return nothing 
end
        
"""
    ismarker(r::Robot)::Bool

-- Проверяет наличие маркера в клетке с роботом
"""
ismarker(r::Robot)::Bool = position(r) ∈ r.situation.markers_map 
    
"""
    temperature(r::Robot)::Int

-- Возвращает значение "температуры" клетки с роботом (на самом деле, всюду за пределами видимой части поля температура равна 0)
"""
temperature(r::Robot)::Int = is_inside(r) ? r.situation.temperature_map[position(r)...] : 0

import Base.show
"""
    show(r::Robot)::Nothing

-- Открывает окно с текущей обстановкой на поле с роботом, при этом невозможно редактирование обстановки с помощью мыши 
(устанавливать/снимать перегородки и/или маркеры, перемещать робота). Если же необходимо иметь возможность 
редактировать показанную обстановку, то вместо show(::Robot) следует использовать функцию show!(::Robot)

    show(sitfile::AbstractString)::Nothing

-- Открывает окно с текущей обстановкой на поле с роботом, загруженной непосредственно из файла. 
Редактирование обстановки невозможно (для редактирования sit-файлов имеется специальная функция sitedit).    
"""
function show(r::Robot) 
    pre_show_actions(r)
    draw(r.situation; newfig=true) 
    r.actualfigure=gcf()
end

"""
    show!(r::Robot)::Nothing

-- Открывает окно с текущей обстановкой на поле с роботом, и предоставляет возможность редактирования
 обстановки с помощью мыши (устанавливать/снимать перегородки и/или маркеры, перемещать робота).
"""
function show!(r::Robot)
    pre_show_actions(r)
    sitedit!(r.situation,"temp.sit")
    # обеспечена возможность редактирования с помощью мыши отображаемой обстановки и немедленного сохранения каждого акта редактирвания в файле temp.sit 
    r.actualfigure=gcf()
    return nothing 
end

function pre_show_actions(r::Robot)
    if r.animate==true
        error("В режиме Robot(...;animate==true) невозможен вызов show(::Robot,...)")
    end
    if isnothing(r.actualfigure)==false
        close(r.actualfigure)
        @warn("Окно с предыдущей обстановкой при открытии нового было автоматически закрыто")
    end
end

show(sitfile::AbstractString) = sitfile!="temp.sit" ? show(Robot(sitfile)) : (@warn "Просмотр temp.sit возможен только с помощью show(::Robot;...)")

"""
    save(r::Robot, sitfile::AbstractString)::Nothing

-- сохраняет обстановку на поле с роботом в указанном текстовом файле    
"""
save(r::Robot, outfile::AbstractString)=save(r.situation,outfile)

"""
    sitedit(infile::AbstractString; outfile=infile)::Nothing

-- предназначена для визуального (с помощью мыши) редактирования обстановки на поле с роботом, предварительно сохраненной в sit-файле. 
Результат редактирования сохораняется в выходном sit-файле (который по умолчанию совпадает с входным sit-файлом)    
Одновременно с этим обстановка сохраняется также в файле "situation.png" (в формате png)
"""
function sitedit(infile::AbstractString; outfile=infile)
    global BUFF_SITUATION, IS_FIXED_ROBOT_POSITION
    BUFF_SITUATION=Situation(infile) #; show(BUFF_SITUATION)
    sitedit!(BUFF_SITUATION, outfile)
end

"""
    sitcreate(num_rows::Integer,num_colons::Integer; newfile="untitled.sit")::Nothing

-- предназначена для создания и визуального (с помощью мыши) редактирования нового sit-файле (содержащего данные некоторой обстановки на поле сроботом). 
По умолчанию имя создаваемого файла - "untitled.sit" 
Одновременно с этим обстановка сохраняется также в файле "situation.png" (в формате png)   
"""    
sitcreate(num_rows::Integer,num_colons::Integer; newfile="untitled.sit") = sitedit!(Situation((num_rows, num_colons)), newfile)

# вспомогательные функции:
is_inside(r::Robot) = SituationData.is_inside(r.situation) # - проверяет, находится ли робот в фрейме (в наблюдаемой части поля)
position(r::Robot) = r.situation.robot_position # - возвращает текущую позицию робота, т.е. - пару индексов (i,j)

end # module HorizonSideRobots

#=
    using .HorizonSideRobots 

    @info "\n*** Включен код с определениями соледующих типов\n\n\t1. @enum HorizonSide Nord=0 West=1 Sud=2 Ost=3 - \"перечисление\", определяет стороны горизонта на клетчатом поле с роботом: \nNord - Север (вверху), West - Запад (слева), Sud - Юг (внизу), Ost - Восток (справа)\n\n\t2. Robot - тип, позволяющий создавать исполнителей \"Робот на клетчатом поле со сторонами горизонта\" \nДля ознакомления со способами использования конструктора Robot и режимами работы см. help?>Robot \n(для перехода в режим help следует набрать в REPL: julia>?+<enter>)\n\n*** Более детальную информацию можно найти на https://github.com/Vibof/Robot"

    const ROBOT_VERSION = "2020 09 08 17-01"

    #inverse(side::HorizonSide) = HorizonSide(mod(Int(side)+2, 4)) 
    #left(side::HorizonSide) = HorizonSide(mod(Int(side)+1, 4))
    #right(side::HorizonSide) = HorizonSide(mod(Int(side)-1, 4))
=#