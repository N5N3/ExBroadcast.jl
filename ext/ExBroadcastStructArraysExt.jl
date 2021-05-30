module ExBroadcastStructArraysExt

using StructArrays
using StructArrays: StructArrayStyle, components
using ExBroadcast
import ExBroadcast: add_style
using ExBroadcast: MultiThreadStyle, TupleArrayStyle
using Base.Broadcast: result_style, Broadcasted, DefaultArrayStyle
import Base.Broadcast: BroadcastStyle
if isdefined(Base.Broadcast, :isivdepsafe)
    # This is definitely not correct.
    Base.Broadcast.isivdepsafe(x::StructArray) = all(Base.Broadcast.isivdepsafe, components(x))
end

function add_style(::Type{MultiThreadStyle{N}}, s::StructArrayStyle{Style}) where {N,Style}
    add_style(MultiThreadStyle{N}, Style()) isa MultiThreadStyle || return s
    MultiThreadStyle{N}(s)
end

add_style(::ExBroadcast.STBFlag, s::BroadcastStyle) =
    result_style(s, StructArrayStyle{DefaultArrayStyle{0},0}())

BroadcastStyle(s1::TupleArrayStyle, s2::StructArrayStyle) = add_style(TupleArrayStyle, result_style(s1.style, s2))
BroadcastStyle(s1::MultiThreadStyle{N}, s2::StructArrayStyle) where {N} = add_style(MultiThreadStyle{N}, result_style(s1.style, s2))

end
