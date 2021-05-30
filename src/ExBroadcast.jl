module ExBroadcast

export @mtb, @tab, @stb, @mtab, @lzb

const NTHREADS = Ref(Threads.nthreads())
@inline num_threads() = NTHREADS[]

"""
    ExBroadcast.set_num_threads(n)
Set the threads' num.
"""
function set_num_threads(n::Int)
    NTHREADS[] = max(1, min(n, Threads.nthreads()))
    nothing
end
include("thread_provider.jl")
include("core_bc_style.jl")
include("util.jl")
include("macro.jl")
include("precompile.jl")

end
