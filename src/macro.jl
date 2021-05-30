struct ExprGuard
    ex::Expr
end

function mapast(f::Function, @nospecialize(ex))
    ex isa Expr || return ex
    for I in eachindex(ex.args)
        ex.args[I] = f(ex.args[I])
    end
    return ex
end

prewalk(f::Function, @nospecialize(ex)) = mapast(Base.Fix1(prewalk, f), f(ex))

"""
:(a .< b .< c < d > 1) =>  :((a .< b .< c) .& (c < d > 1))
"""
function splitcomparison(ex::Expr, temp = gensym(:temp))
    exprs = Any[]
    exprs′ = Any[]
    ex = prewalk(ex) do ex
        if (ex isa Expr && ex.head !== :comparison) || ex isa ExprGuard
            sym = Symbol(temp, '_', length(exprs))
            push!(exprs, Expr(:local, Expr(:(=), sym, ex)))
            return sym
        end
        return ex
    end
    I = I′ = 2
    dot = first(string(ex.args[2])) === '.'
    for outer I′ in 4:2:length(ex.args)
        dot′ = first(string(ex.args[I′])) === '.'
        if dot != dot′
            ex′ = I′  == I + 2 ?
                Expr(:call, ex.args[I], ex.args[I-1], ex.args[I+1]) :
                Expr(:comparison, ex.args[I-1:I′-1]...)
            push!(exprs′, ex′)
            I = I′
            dot = dot′
        end
    end
    ex = I′ == I ?
        Expr(:call, ex.args[I], ex.args[I-1], ex.args[I+1]) :
        Expr(:comparison, ex.args[I-1:end]...)
    push!(exprs′, ex)
    ex = foldl(exprs′) do x, y
        Expr(:call, :.&, x, y)
    end
    push!(exprs, ex)
    ex = Expr(:block)
    ex.args = exprs
    return ex
end

function isdot(ex)
    ex isa Expr || return false
    if ex.head === :.
        return Meta.isexpr(ex.args[2], :tuple)
    elseif ex.head === :call
        return ex.args[1] isa Symbol && first(string(ex.args[1])) === '.'
    elseif ex.head === :comparison
        return first(string(ex.args[2])) === '.'
    else
        return first(string(ex.head)) === '.'
    end
end

function lowerdot(mod::Module, ex::Expr, temp = gensym(:temp))
    exprs = Any[]
    ex = prewalk(ex) do ex
        if isdot(ex) || Meta.isexpr(ex, (:tuple, :parameters, :...))
            if ex.head === :(.=) && Meta.isexpr(ex.args[1], :ref)
                ex.args[1] = Expr(:call, GlobalRef(Base, :dotview), ex.args[1].args...)
            end
            return ex
        elseif ex isa Expr || ex isa ExprGuard
            sym = Symbol(temp, '_', length(exprs))
            push!(exprs, Expr(:local, Expr(:(=), sym, ex)))
            return sym
        else
            return ex
        end
    end
    ci = Meta.lower(mod, ex)
    ci.head === :error && error(ci.args[1])
    (;code, slotnames) = only(ci.args)
    isempty(slotnames) || error("Internal error! Please file a bug!")
    for I = 1:length(code) - 1
        ex = prewalk(code[I]) do ex
            if ex isa Core.SSAValue
                return Symbol("ssa_", temp, '_', ex.id)
            elseif ex isa Core.SlotNumber
                error("Internal error! Please file a bug!")
            else
                return ex
            end
        end
        code[I] = Expr(:local, Expr(:(=), Symbol("ssa_", temp, '_', I), ex))
    end
    ansid = ((code[end]::Core.ReturnNode).val::Core.SSAValue).id
    code[end] = Symbol("ssa_", temp, '_', ansid)
    append!(exprs, code)
    ex = Expr(:block)
    ex.args = exprs
    return ex
end

function lowerhack(mod::Module, ex::Expr, @nospecialize exargs...)
    temp = gensym(:temp)
    count = Ref(0)
    ex = prewalk(ex) do ex
        if Meta.isexpr(ex, :->, 2) ||
            Meta.isexpr(ex, :function) ||
            (Meta.isexpr(ex, :(=), 2) && Meta.isexpr(ex.args[1], :call))
            # guard all method definitions
            return ExprGuard(ex)
        elseif Meta.isexpr(ex, :macrocall) &&
            (ex.args[1] === Symbol("@__dot__") ||
             ex.args[1] === Base.var"@__dot__")
            # expand all @.
            return Expr(:block, ex.args[2], Base.Broadcast.__dot__(ex.args[3]))
        elseif Meta.isexpr(ex, :comparison)
            # split all :comparison if needed
            dot = first(string(ex.args[2])) === '.'
            needsplit = false
            for I in 4:2:length(ex.args)
                dot′ = first(string(ex.args[I])) === '.'
                if dot != dot′
                    temp′ = Symbol(temp, count[])
                    count[] += 1
                    return splitcomparison(ex, temp′)
                end
            end
        end
        return ex
    end
    # 2 lower all dot calls
    ex = prewalk(ex) do ex
        if isdot(ex)
            temp′ = Symbol(temp, count[])
            count[] += 1
            return lowerdot(mod, ex, temp′)
        else
            return ex
        end
    end
    # 3 a) format do (if needed)
    # 3 b) expand broadcast(!) (if needed)
    # 3 c) insert style
    ex = prewalk(ex) do ex
        if Meta.isexpr(ex, :do, 2)
            ex, fun = ex.args
            pushfirst!(ex.args, ex.args[1])
            ex.args[2] = fun
        end
        if Meta.isexpr(ex, :call)
            func = ex.args[1]
            if func === :broadcast
                ex.args[1] = GlobalRef(Base, :broadcasted)
                func = GlobalRef(Base, :materialize)
                ex = Expr(:call, func, ex)
            elseif func === :broadcast!
                ex′ = Expr(:call, GlobalRef(Base, :broadcasted), ex.args[2], ex.args[4:end]...)
                func = GlobalRef(Base, :materialize!)
                ex = Expr(:call, func, ex.args[3], ex′)
            end
            if func === GlobalRef(Base, :materialize) ||
                (Meta.isexpr(func, :., 2) &&
                 func.args[1] === :Base &&
                 func.args[2] === QuoteNode(:materialize))
                ex.args[2] = :($extend_style($(ex.args[2]), $(exargs...)))
            elseif func === GlobalRef(Base, :materialize!) ||
                   (Meta.isexpr(func, :., 2) &&
                    func.args[1] === :Base &&
                    func.args[2] === QuoteNode(:materialize!))
                ex.args[3] = :($extend_style($(ex.args[3]), $(exargs...)))
                if exargs[1] === TupleArrayStyle
                    ex.args[2] = :($TupleDummy($(ex.args[2])))
                end
            end
        end
        return ex
    end
    # 4. drop ExprGuard
    return prewalk(ex) do ex
        ex isa ExprGuard ? ex.ex : ex
    end
end

"""
**Example:**
```julia
@mtb @. a = sin(c)
@mtb a = sin.(c)
@mtb broadcast!(sin,a,c)
@mtb a = broadcast!(sin,c)
@mtb 2 a = broadcast!(sin,c) # use 2 threads
```
"""
macro mtb(args...)
    na = length(args)
    if na == 1
        nthread, ex = num_threads(), args[1]
    elseif na == 2
        nthread, ex = args
    else
        error("Invalid input")
    end
    isa(nthread, Integer) || throw(ArgumentError("`num_thread` must be an `Integer`"))
    nthread = min(nthread, Threads.nthreads())
    nthread <= 1 && return esc(ex)
    return esc(lowerhack(@__MODULE__, ex, MultiThreadStyle{nthread}))
end

"""
**Example:**
```julia
@tab @. (a,b) = sincos(c)
@tab @. a,b = sincos(c)
@tab (a,b) = @. sincos(c)
```
**Note:**
@tab is needed only for non in-place situation.
"""
macro tab(ex)
    esc(lowerhack(@__MODULE__, ex, TupleArrayStyle))
end

"""
    @mtab [n] ex = @mtb [n] @tab ex
"""
macro mtab(args...)
     na = length(args)
    if na == 1
        nthread, ex = num_threads(), args[1]
    elseif na == 2
        nthread, ex = args
    else
        error("Invalid input")
    end
    (!isa(nthread, Integer) || nthread <= 1) &&
        return esc(lowerhack(@__MODULE__, ex, TupleArrayStyle))
    nthread = min(nthread, Threads.nthreads())
    return esc(lowerhack(@__MODULE__, ex, TupleArrayStyle, MultiThreadStyle{nthread}))
end

"""
    @lzb  return lazy Broadcasted object
"""
macro lzb(ex)
    esc(lowerhack(@__MODULE__, ex, LazyStyle))
end

struct STBFlag end
"""
    @stb force struct broadcast
    you need load StructArrays to make it work
"""
macro stb(ex)
    esc(lowerhack(@__MODULE__, ex, STBFlag()))
end
