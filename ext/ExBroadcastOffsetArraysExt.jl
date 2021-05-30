module ExBroadcastOffsetArraysExt
using OffsetArrays, ExBroadcast
if isdefined(Base.Broadcast, :isivdepsafe)
    Base.Broadcast.isivdepsafe(x::OffsetArray) = Base.Broadcast.isivdepsafe(x.parent)
end
end
