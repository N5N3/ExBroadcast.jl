module ExBroadcastAdaptExt
import ExBroadcast: TupleDummy
import Adapt: adapt_structure, adapt
adapt_structure(to, td::TupleDummy{T,N,L}) where {T,N,L} =
    TupleDummy{T,N,L}(adapt(to, td.arrays), td.ax)
end
