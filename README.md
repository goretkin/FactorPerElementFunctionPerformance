See https://discourse.julialang.org/t/factor-out-field-access-of-abstractarray-and-or-iterator-interface/41493

Main symptom:

```julia
foo2(tx5(a1000, :field))
```

is many times slower than

```julia
foo3(Base.Fix2(getfield, :field), a1000)
```

Defining

```julia
import MappedArrays

function Base.iterate(A::MappedArrays.ReadonlyMappedArray, args...)
    r = iterate(A.data, args...)
    r === nothing && return r
    return (A.f(r[1]), r[2])
end
```

makes the gap disappear.
