
import Base: size, axes, setindex!, unalias, unaliascopy, IndexStyle, parent
using Base: unsafe_setindex!, tail, mightalias, axes1

### import many funtions
using Base.Broadcast: Broadcasted, AbstractArrayStyle, Style, DefaultArrayStyle
import Base.Broadcast: broadcast_unalias, BroadcastStyle, Unknown
using Base.Broadcast: throwdm, ischunkedbroadcast, chunkedcopyto!, bitcache_size,
    dumpbitcache, bitcache_chunks, BroadcastStyle, combine_styles, instantiate,
    broadcastable, Style, _broadcast_getindex, result_style

struct LazyStyle{P<:BroadcastStyle} <: BroadcastStyle
    style::P
    LazyStyle(style) = new{typeof(style)}(style)
end
struct TupleArrayStyle{P<:BroadcastStyle} <: BroadcastStyle
    style::P
    TupleArrayStyle(style) = new{typeof(style)}(style)
end
struct MultiThreadStyle{N,P<:BroadcastStyle} <: BroadcastStyle
    style::P
    MultiThreadStyle{N}(style) where {N} = new{N,typeof(style)}(style)
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
extend_style(x) = x
extend_style(x, s, args...) = extend_style(add_style(s, x), args...)
add_style(s, x) = x
add_style(s, bc::Broadcasted) = adopt_style(bc, add_style(s, bc.style))
add_style(::Type{LazyStyle}, s::BroadcastStyle) = LazyStyle(s)

add_style(::Type{TupleArrayStyle}, s::BroadcastStyle) = TupleArrayStyle(s)
add_style(::Type{TupleArrayStyle}, s::TupleArrayStyle) = s
add_style(::Type{TupleArrayStyle}, s::Unknown) = s
add_style(::Type{TupleArrayStyle}, s::MultiThreadStyle{N}) where {N} =
    add_style(MultiThreadStyle{N}, add_style(TupleArrayStyle, s.style))

add_style(::Type{MultiThreadStyle{N}}, s::BroadcastStyle) where {N} = MultiThreadStyle{N}(s)
add_style(::Type{MultiThreadStyle{N}}, s::Unknown) where {N} = s
add_style(::Type{MultiThreadStyle{N}}, s::Style{Tuple}) where {N} = s
add_style(::Type{MultiThreadStyle{N}}, s::MultiThreadStyle{M}) where {N,M} = add_style(MultiThreadStyle{min(M,N)}, s.style)
function add_style(::Type{MultiThreadStyle{N}}, s::TupleArrayStyle) where {N}
    add_style(MultiThreadStyle{N}, s.style) isa MultiThreadStyle || return s
    MultiThreadStyle{N}(s)
end

BroadcastStyle(s1::BroadcastStyle, s2::TupleArrayStyle) = add_style(TupleArrayStyle, result_style(s1, s2.style))
BroadcastStyle(s1::TupleArrayStyle, s2::DefaultArrayStyle) = add_style(TupleArrayStyle, result_style(s1.style, s2))
BroadcastStyle(s1::DefaultArrayStyle, s2::MultiThreadStyle{N}) where {N} = add_style(MultiThreadStyle{N}, result_style(s1, s2.style))
BroadcastStyle(s1::MultiThreadStyle{N}, s2::DefaultArrayStyle) where {N} = add_style(MultiThreadStyle{N}, result_style(s1.style, s2))
