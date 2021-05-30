module ExBroadcastStructArraysExt

using StructArrays
using StructArrays: StructArrayStyle, components
using ExBroadcast
import ExBroadcast: add_style, lowerhack, macro_key, var"@stb"
using ExBroadcast: MultiThreadStyle, TupleArrayStyle
using Base.Broadcast: result_style, Broadcasted, DefaultArrayStyle
using Base.Broadcast: BroadcastStyle
if isdefined(Base.Broadcast, :isivdepsafe)
    # This is definitely not correct.
    Base.Broadcast.isivdepsafe(x::StructArray) = all(Base.Broadcast.isivdepsafe, components(x))
end

function add_style(::Type{MultiThreadStyle}, s::StructArrayStyle{Style}, n::Integer) where {Style}
    add_style(MultiThreadStyle, Style(), n) isa MultiThreadStyle || return s
    MultiThreadStyle(s, n)
end

add_style(::Type{StructArrayStyle}, s::BroadcastStyle) =
    result_style(s, StructArrayStyle{DefaultArrayStyle{0},0}())

macro stb(ex)
    esc(lowerhack(ex, macro_key(StructArrayStyle)))
end

Broadcast.BroadcastStyle(s1::TupleArrayStyle, s2::StructArrayStyle) = add_style(TupleArrayStyle, result_style(s1.style, s2))
Broadcast.BroadcastStyle(s1::MultiThreadStyle, s2::StructArrayStyle) = add_style(MultiThreadStyle, result_style(s1.style, s2), s1.nthread)

end
