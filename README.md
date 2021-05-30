# ExBroadcast.jl
* Extend `Base.Broadcast` by macros:
  *  `@tab`: Tuple of Array Broadcast --- broadcast with multiple outputs will be stored in tuple of array (instead of array of tuple). 
  *  `@mtb`: MultiThread Broadcast --- perform broadcast with multiple threads. 
  *  `@mtab`: `@mtb` + `@tab`
  *  `@stb`: force STructArray Broadcast --- it only works if user loads `StructArrays.jl`
## Macros' Usage
1. `@tab` : support `CuArray`, `OffsetArray`, `Tuple`, `StructArray`, `StaticArray`
```julia
julia> a = randn(4000,4000);
julia> @tab b, c = sincos.(a);
julia> @tab b, c = broadcast(sincos,a);
julia> @tab b, c = broadcast(a) do x
          sincos(x)
       end;
julia> @tab b, c .= sincos.(a);
julia> broadcast!(sincos,(b,c),a);
```
* For `outputs <: AbstractArray`
  * Only the default `copy` method which use `similar(bc, T)` is implemented, thus inputs like `StaticArray` is not allowed for non-inplace caluculation by default. We have an extension for `@tab` with `StaticArrays`.
  * `@tab` is not optimized for BitArray. The default return type is Array{Bool} for non-inplace broadcast.
* For `outputs <: Tuple`, `@tab` first generate all results and then seperate them. 
* `@tab` is not designed for too many outputs.

2. `@mtb` : cpu multi-threads broadcast
```julia
julia> a = randn(4000,4000); b = similar(a);
julia> @btime @mtb @. $b = sin(a);
  47.756 ms (22 allocations: 2.97 KiB)
julia> @btime @. $b = sin(a);
  167.985 ms (2 allocations: 32 bytes)
julia> Threads.nthreads()
 4
```
* `@mtb` use `CartesianPartition` to seperate the task with dimension > 1
* `@mtb` will be turned off automately for `CuArray` and `Tuple`
* `@mtb` assume all elements in the dest array(s) are seperated in the memory and there's no thread safety check.
* `@mtb` is not tuned for small arrays (It won't invoke the single thread version automately). 
* User can change the number of threads by :
   * Call `ExBroadcast.set_num_threads(n)` for global change.
   * Use 2 inputs macro `@mtb n [...]` for local change. (thread safe)

## Note
1. `@mtab` only save some compile cost.
