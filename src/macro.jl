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
function splitcomparison(ex::Expr)
    @assert Meta.isexpr(ex, :comparison)
    args = ex.args
    @assert isodd(length(args))
    st, la, dot = 2, 2, first(string(args[2])) === '.'
    ex = nothing
    for I = 4:2:length(args)-1
        dot′ = first(string(args[I])) === '.'
        if dot == dot′
            la = I
        else
            ex′ = if st == la
                Expr(:call, args[st], args[st-1], args[st+1])
            else
                Expr(:comparison, @view(args[st-1:la+1])...)
            end
            ex = ex === nothing ? ex′ : Expr(:call, GlobalRef(Base, :broadcasted), &, ex, ex′)
            st = la = I
            dot = dot′
        end
    end
    ex′ = if st == la
        Expr(:call, args[st], args[st-1], args[st+1])
    else
        Expr(:comparison, @view(args[st-1:la+1])...)
    end
    return ex === nothing ? ex′ : Expr(:call, Symbol(".&"), ex, ex′)
end

function isdot(ex)
    isdotop(x::String) =
        length(x) > 1 && x[1] == '.' && x[2] != '.'
    ex isa Expr || return false
    if ex.head === :.
        return length(ex.args) == 2 && Meta.isexpr(ex.args[2], :tuple)
    elseif ex.head === :call
        return ex.args[1] isa Symbol && isdotop(string(ex.args[1]))
    elseif ex.head === :comparison
        return isdotop(string(ex.args[2]))
    else
        return isdotop(string(ex.head))
    end
end

lower_dotview(ex) =
    Meta.isexpr(ex, :ref) ? Expr(:call, GlobalRef(Base, :dotview), ex.args...) :
    Meta.isexpr(ex, :tuple) ? Expr(:tuple, Iterators.map(lower_dotview, ex.args)...) :
    ex

function lowerdot(ex::Expr)
    shead = string(ex.head)       
    ex′ = prewalk(ex) do ex
        isdot(ex) || return ex
        if ex.head === :.
            @assert(length(ex.args) == 2)
            op, tu = ex.args
            @assert(Meta.isexpr(tu, :tuple))
            args = tu.args
            if Meta.isexpr(args[1], :parameters)
                return Expr(:call, GlobalRef(Base, :broadcasted_kwsyntax), args[1], op, @view(args[2:end])...)
            elseif op == :^ && length(args) == 2 && args[2] isa Integer
                # special handling for .^ with integer exponent
                base, exp = args[1], args[2]
                return Expr(:call, GlobalRef(Base, :broadcasted), GlobalRef(Base, :literal_pow), op, base, Val(exp))
            else
                return Expr(:call, GlobalRef(Base, :broadcasted), op, args...)
            end
        elseif ex.head === :call
            dotop = ex.args[1]
            @assert(dotop isa Symbol && first(string(dotop)) === '.')
            op = Symbol(string(dotop)[2:end])
            if op === :^ && length(ex.args) == 3 && ex.args[3] isa Integer
                # special handling for .^ with integer exponent
                base, exp = ex.args[2], ex.args[3]
                return Expr(:call, GlobalRef(Base, :broadcasted), GlobalRef(Base, :literal_pow), op, base, Val(exp))
            end
            return Expr(:call, GlobalRef(Base, :broadcasted), op, @view(ex.args[2:end])...)
        elseif ex.head === :comparison
            args = ex.args
            @assert(isodd(length(args)))
            mapped = Iterators.map(2:2:length(args)-1) do I
                dotop = ex.args[I]
                @assert(first(string(dotop)) === '.')
                op = Symbol(string(dotop)[2:end])
                Expr(:call, GlobalRef(Base, :broadcasted), op, args[I-1], args[I+1])
            end
            return foldl(mapped) do x, y
                Expr(:call, GlobalRef(Base, :broadcasted), &, x, y)
            end
        else
            dotop, args = ex.head, ex.args
            if dotop === :(.&&) || dotop === :(.||)
                op = dotop === :(.&&) ? Base.andand : Base.oror
                return Expr(:call, GlobalRef(Base, :broadcasted), op, args...)
            elseif dotop === :(.=)
                return Expr(:call, GlobalRef(Base, :materialize!), lower_dotview(args[1]), @view(args[2:end])...)
            else
                @assert(string(dotop)[1] === '.' && string(dotop)[end] === '=')
                op = Symbol(string(dotop)[2:end-1])
                return Expr(:call, GlobalRef(Base, :materialize!), lower_dotview(args[1]), Expr(:call, GlobalRef(Base, :broadcasted), op, args...))
            end
        end
    end
    if first(shead) !== '.' || last(shead) !== '='
        ex′ = Expr(:call, GlobalRef(Base, :materialize), ex′)
    end
    return ex′
end

function lowerhack(ex::Expr, @nospecialize exargs...)
    # stage 1
    ex = prewalk(ex) do ex
        if Base.is_function_def(ex)
            # guard all method definitions
            return ExprGuard(ex)
        elseif Meta.isexpr(ex, :macrocall) &&
            (ex.args[1] === Symbol("@__dot__") ||
             ex.args[1] === Base.var"@__dot__")
            # expand all @.
            return Expr(:block, ex.args[2], Base.Broadcast.__dot__(ex.args[3]))
        elseif Meta.isexpr(ex, :comparison)
            # split all :comparison if needed
            return splitcomparison(ex)
        end
        return ex
    end
    # stage 2 
    ex = prewalk(ex) do ex
        if Meta.isexpr(ex, :do, 2)
            ex, fun = ex.args
            pushfirst!(ex.args, ex.args[1])
            ex.args[2] = fun
        end
        if isdot(ex) # lower all dot calls
            ex = lowerdot(ex)
        end
        if Meta.isexpr(ex, :call)
            func = ex.args[1]
            # expand broadcast(!)
            if func === :broadcast
                ex.args[1] = GlobalRef(Base, :broadcasted)
                func = GlobalRef(Base, :materialize)
                ex = Expr(:call, func, ex)
            elseif func === :broadcast!
                ex′ = Expr(:call, GlobalRef(Base, :broadcasted), ex.args[2], ex.args[4:end]...)
                func = GlobalRef(Base, :materialize!)
                ex = Expr(:call, func, ex.args[3], ex′)
            end
            # insert style
            if func === GlobalRef(Base, :materialize) ||
                (Meta.isexpr(func, :., 2) &&
                 func.args[1] === :Base &&
                 func.args[2] === QuoteNode(:materialize))
                ex.args[2] = Expr(:call, extend_style, ex.args[2], exargs...)
            elseif func === GlobalRef(Base, :materialize!) ||
                (Meta.isexpr(func, :., 2) &&
                 func.args[1] === :Base &&
                 func.args[2] === QuoteNode(:materialize!))
                ex.args[3] = Expr(:call, extend_style, ex.args[3], exargs...)
                if any(ex->ex.args[1] === Extend{TupleArrayStyle} ,exargs)
                    ex.args[2] = Expr(:call, TupleDummy, ex.args[2])
                end
            end
        end
            return ex
    end
    # drop ExprGuard
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
        nthread, ex = Expr(:call, GlobalRef(ExBroadcast, :num_threads)), args[1]
    elseif na == 2
        nthread, ex = args
    else
        error("Invalid input")
    end
    if nthread isa Integer && nthread <= 1
        return esc(ex)
    end
    return esc(lowerhack(ex, macro_key(MultiThreadStyle, nthread)))
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
    esc(lowerhack(ex, macro_key(TupleArrayStyle)))
end

"""
    @mtab [n] ex = @mtb [n] @tab ex
"""
macro mtab(args...)
     na = length(args)
    if na == 1
        nthread, ex = Expr(:call, GlobalRef(ExBroadcast, :num_threads)), args[1]
    elseif na == 2
        nthread, ex = args
    else
        error("Invalid input")
    end
    if nthread isa Integer && nthread <= 1
        return esc(lowerhack(ex, macro_key(:tab)))
    end
    return esc(lowerhack(ex, macro_key(TupleArrayStyle), macro_key(MultiThreadStyle, nthread)))
end

"""
    @lzb  return lazy Broadcasted object
"""
macro lzb(ex)
    esc(lowerhack(ex, macro_key(LazyStyle)))
end

"""
    @stb force struct broadcast
    you need load StructArrays to make it work
"""
macro stb end

macro_key(::Type{T}, args...) where {T} = Expr(:call, Extend{T}, args...)
