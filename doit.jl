using Test
using BenchmarkTools
using DataStructures: OrderedDict

using MappedArrays: mappedarray

# use the iterator interface
function foo(a)
    r = nothing
    for x in a
        y = x.field
        if r === nothing
            r = y
        else
            r += y
        end
    end
    return r
end

# use the `AbstractArray` interface
function bar(a)
    T = fieldtype(eltype(typeof(a)), :field)
    return a[3].field + one(T)
end

function foo2(a)
    r = nothing
    for y in a
        if r === nothing
            r = y
        else
            r += y
        end
    end
    return r
end

function bar2(a)
    T = eltype(typeof(a))
    return a[3] + one(T)
end

a = [(field=i,) for i = 1:5]
b = ((field=i,) for i in Iterators.TakeWhile(<=(5), Iterators.Count(1,1)))  # has `Any` `eltype`
c = Iterators.TakeWhile(x->true, a) # has an `eltype`

@test foo(a) == 15
@test foo(b) == 15
@test foo(c) == 15
@test bar(a) == 4


# materialize an intermediate array
tx1(A, f) = getfield.(A, Ref(f))

@test foo2(tx1(a, :field)) == foo(a)
@test foo2(tx1(b, :field)) == foo(b)
@test foo2(tx1(c, :field)) == foo(c)
@test bar2(tx1(a, :field)) == bar(a)

# don't materialize an intermediate array
tx2(A, f) = (getfield(x, f) for x in A)

@test foo2(tx2(a, :field)) == foo(a)
@test foo2(tx2(b, :field)) == foo(b)
@test foo2(tx2(c, :field)) == foo(c)
@test_throws Any bar2(tx2(a, :field)) == bar(a) # but `tx2` doesn't preserve the `AbstractArray` interface

# don't materialize an intermediate array
tx3(A, f) = mappedarray(Base.Fix2(getfield, f), A)

@test foo2(tx3(a, :field)) == foo(a)
@test_throws Any foo2(tx3(b, :field)) == foo(b) # but `tx3` requires the `AbstractArray` interface
@test_throws Any foo2(tx3(c, :field)) == foo(c) # ditto
@test bar2(tx3(a, :field)) == bar(a)

lazy_map(f, A::AbstractArray) = mappedarray(f, A)
lazy_map(f, A) = (f(x) for x in A)

tx4(A, f) = lazy_map(Base.Fix2(getfield, f), A)

@test foo2(tx4(a, :field)) == foo(a)
@test foo2(tx4(b, :field)) == foo(b)
@test foo2(tx4(c, :field)) == foo(c)
@test bar2(tx4(a, :field)) == bar(a)
@show eltype(tx4(c, :field))            # but `tx4` doesn't have right `eltype` since generators do not infer `eltype`

# force the `eltype` of the generator to be G
struct TypedGenerator{T, G}
    g::G
end
Base.eltype(::Type{TypedGenerator{T, G}}) where {T, G} = T
Base.axes(g::TypedGenerator) = axes(g.g)
Base.collect(g::TypedGenerator) = collect(g.g)
Base.iterate(g::TypedGenerator, args...) = iterate(g.g, args...)
Base.length(g::TypedGenerator) = length(g.g)
Base.ndims(g::TypedGenerator) = ndims(g.g)
# Base.nextind(g::TypedGenerator, args...) = nextind(g.g, args...)    # AbstractTrees defines this
Base.size(g::TypedGenerator) = size(g.g)
Base.IteratorSize(::Type{TypedGenerator{T, G}}) where {T ,G} = Base.IteratorSize(G)

TypedGenerator{T}(g) where {T} = TypedGenerator{T, typeof(g)}(g)

tg = TypedGenerator{Int64}((x for x in Iterators.TakeWhile(<(5), Iterators.Count(1, 1))))
tg2 = TypedGenerator{Int64}((x for x in [1,2,3]))


fieldtype_any(T::Type{Any}, f) = Any
fieldtype_any(T::Type{<:Any}, f) = fieldtype(T, f)

lazy_map2(f, A::AbstractArray) = mappedarray(f, A)
lazy_map2(f::Base.Fix2{typeof(getfield)}, A) = TypedGenerator{fieldtype_any(eltype(A), f.x)}(f(x) for x in A)
lazy_map2(f::Base.Fix2{typeof(getfield)}, A::AbstractArray) = mappedarray(f, A) # resolve ambiguity

tx5(A, f) = lazy_map2(Base.Fix2(getfield, f), A)

@test foo2(tx5(a, :field)) == foo(a)
@test foo2(tx5(b, :field)) == foo(b)
@test foo2(tx5(c, :field)) == foo(c)
@test bar2(tx5(a, :field)) == bar(a)
@test eltype(tx5(c, :field)) == Int64            # `tx5` has right `eltype`


a1000 = [(field=i,) for i = 1:1000]
b1000 = ((field=i,) for i in Iterators.TakeWhile(<=(1000), Iterators.Count(1,1)))  # has `Any` `eltype`
c1000 = Iterators.TakeWhile(x->true, a1000) # has an `eltype`

B = OrderedDict{Any, Any}()

for (abc, abc_s) = zip((a1000, b1000, c1000), (:a, :b, :c))
    println("\n\n-------------------------------------------------")
    @show abc_s

    b = B[(abc_s, :unfactored)] = @benchmark foo($abc)

    println("unfactored")
    show(stdout, "text/plain", b); println(stdout)

    b = B[(abc_s, :factored)] = @benchmark foo2(tx5($abc, :field))

    println("\n\nfactored")
    show(stdout, "text/plain", b); println(stdout)
end
