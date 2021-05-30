module ExBroadcastStaticArraysExt
using StaticArrays: StaticArrayStyle, similar_type, Size, SOneTo
using StaticArrays: broadcast_flatten, broadcast_sizes, first_statictype, __broadcast
using ExBroadcast
using ExBroadcast: MultiThreadStyle, TupleArrayStyle
using Base.Broadcast: Broadcasted
ExBroadcast.add_style(::Type{MultiThreadStyle}, s::StaticArrayStyle, ::Integer) = s
@inline function Base.copy(bc::Broadcasted{TupleArrayStyle{StaticArrayStyle{M}}}) where {M}
    (;args, f) = broadcast_flatten(bc)
    argsizes = broadcast_sizes(args...)
    ax = axes(bc)
    ax isa Tuple{Vararg{SOneTo}} || error("Dimension is not static. Please file a bug.")
    return _broadcast(f, Size(map(length, ax)), argsizes, args...)
end

@inline function _broadcast(f, sz::Size{newsize}, s::Tuple{Vararg{Size}}, a...) where {newsize}
    first_staticarray = first_statictype(a...)
    elements, ET = if prod(newsize) == 0
        # Use inference to get eltype in empty case (see also comments in _map)
        eltys = Tuple{map(eltype, a)...}
        (), Core.Compiler.return_type(f, eltys)
    else
        temp = __broadcast(f, sz, s, a...)
        temp, eltype(temp)
    end
    ET <: Tuple{Any,Vararg{Any}} || throw(ArgumentError(lazy"$ET is not a legal return type for @tab!"))
    return ntuple(Val(fieldcount(ET))) do i
        @inbounds similar_type(first_staticarray, fieldtype(ET, i), sz)(_getfields(elements, i))
    end
end

@inline function _getfields(x::Tuple, i::Int)
    if @generated
        Expr(:tuple, (:(getfield(x[$j], i)) for j in 1:fieldcount(x))...)
    else
        map(Base.Fix2(getfield, i), x)
    end
end

end 
