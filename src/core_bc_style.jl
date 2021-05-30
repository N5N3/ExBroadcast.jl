
import Base: size, axes, setindex!, unalias, unaliascopy, IndexStyle, parent
using Base: unsafe_setindex!, tail, mightalias, axes1

### import many funtions
using Base.Broadcast: Broadcasted, 
    BroadcastStyle, AbstractArrayStyle, Style, DefaultArrayStyle,
    throwdm, ischunkedbroadcast, chunkedcopyto!, bitcache_size,
    dumpbitcache, bitcache_chunks, BroadcastStyle, combine_styles, instantiate,
    broadcastable, _broadcast_getindex, result_style, Unknown

struct LazyStyle{P<:BroadcastStyle} <: BroadcastStyle
    style::P
    LazyStyle(style) = new{typeof(style)}(style)
end
struct TupleArrayStyle{P<:BroadcastStyle} <: BroadcastStyle
    style::P
    TupleArrayStyle(style) = new{typeof(style)}(style)
end
struct MultiThreadStyle{P<:BroadcastStyle} <: BroadcastStyle
    style::P
    nthread::Int
    MultiThreadStyle(style, n) = new{typeof(style)}(style, n)
end

## for compution 
# mtb
include("macro_kernal/mtb.jl")
# tab
include("macro_kernal/tab.jl")
# lzb
Base.copy(bc::Broadcasted{<:LazyStyle}) = adopt_style(bc, bc.style.style)
Base.materialize!(dest, bc::Broadcasted{<:LazyStyle}) = throw(ArgumentError("@lzb doesn't support broadcast!"))

## for style overload
struct Extend{S<:BroadcastStyle,T}
    args::T
    Extend{S}(args...) where {S} = new{S,typeof(args)}(args)
end
extend_style(x) = x
extend_style(x, s::Extend{S}, args...) where {S} = extend_style(add_style(S, x, s.args...), args...)
add_style(_, x, args...) = x
add_style(s, bc::Broadcasted, args...) = adopt_style(bc, add_style(s, bc.style, args...))
add_style(::Type{LazyStyle}, s::BroadcastStyle) = LazyStyle(s)

add_style(::Type{TupleArrayStyle}, s::BroadcastStyle) = TupleArrayStyle(s)
add_style(::Type{TupleArrayStyle}, s::TupleArrayStyle) = s
add_style(::Type{TupleArrayStyle}, s::Unknown) = s
add_style(::Type{TupleArrayStyle}, s::MultiThreadStyle) =
    add_style(MultiThreadStyle, add_style(TupleArrayStyle, s.style), s.nthread)

add_style(::Type{MultiThreadStyle}, s::BroadcastStyle, n::Integer) = MultiThreadStyle(s, n)
add_style(::Type{MultiThreadStyle}, s::Unknown, ::Integer) = s
add_style(::Type{MultiThreadStyle}, s::Style{Tuple}, ::Integer) = s
add_style(::Type{MultiThreadStyle}, s::MultiThreadStyle, n::Integer) = add_style(MultiThreadStyle, s.style, min(n, s.nthread))
function add_style(::Type{MultiThreadStyle}, s::TupleArrayStyle, n::Integer)
    add_style(MultiThreadStyle, s.style, n) isa MultiThreadStyle || return s
    MultiThreadStyle(s, n)
end

Broadcast.BroadcastStyle(s1::BroadcastStyle, s2::TupleArrayStyle) = add_style(TupleArrayStyle, result_style(s1, s2.style))
Broadcast.BroadcastStyle(s1::TupleArrayStyle, s2::DefaultArrayStyle) = add_style(TupleArrayStyle, result_style(s1.style, s2))
Broadcast.BroadcastStyle(s1::DefaultArrayStyle, s2::MultiThreadStyle) = add_style(MultiThreadStyle, result_style(s1, s2.style), s2.nthread)
Broadcast.BroadcastStyle(s1::MultiThreadStyle, s2::DefaultArrayStyle) = add_style(MultiThreadStyle, result_style(s1.style, s2), s1.nthread)