"""
    SampleSpace

Defines restrictions on the sample space of a two-stage design to be used during
optimization.
""" 
mutable struct SampleSpace{TI<:Integer,TR<:Real}

  n1range::Vector{TI}
  nmax::TI
  n2min::TI
  maxnfact::TR
  nmincont::TI
  maxvariables::TI
  GS::Bool # group sequential ?
  specialnvalues::Vector{TI} # required for additional values always included in nvals
  specialcvalues::Vector{TI}

  function SampleSpace{TI,TR}(
    n1range::Vector{TI}, 
    nmax::TI, 
    n2min::TI, 
    maxnfact::TR, 
    nmincont::TI, 
    maxvariables::TI,
    GS::Bool
  ) where {TI<:Integer,TR<:Real}

    minimum(n1range) < 1    ? error("minimal n1 must be >= 1")    : nothing
    maximum(n1range) > nmax ? error("maximal n1 must be <= nmax") : nothing
    maxvariables < 100      ? error("maxvariables must be >= 100") : nothing
    maxnfact = (maxnfact == Inf) ? nmax / minimum(n1range) : maxnfact
    new(sort(n1range), nmax, n2min, maxnfact, nmincont, maxvariables, GS, convert(Vector{TI}, zeros(0)), convert(Vector{TI}, zeros(0)))

  end # inner constructor (SampleSpace)

end # SampleSpace


"""
    SampleSpace(
      n1range,
      nmax::TI;
      n2min::TI = 1, 
      maxnfact::TR = Inf, 
      nmincont::TI = 0, 
      maxvariables::TI = 500000, 
      GS::Bool = false
    ) where {TI<:Integer,TR<:Real}

Creates a [`SampleSpace`](@ref)-object which defines the search space for finding 
optimal two-stage designs using [`optimaldesign`](@ref).
The primary use of dedicated sample sapce objects is the incoporation of 
specific operational constraints on optimal designs (e.g. maximal sample size).

# Parameters

| Parameter      | Description |
| -------------: | :---------- |
| n1range        | possible stage-one sample sizes, can be anything which is convertable to an integer vector |
| nmax           | maximal overall sample size (stage one and two combined) |
| [n2min]        | minimal stage-two sample size |
| [maxnfact]     | maximal overall sample size must be smaller than `maxnfact * n1`  |
| [nmincont]     | minimal sample size upon rejection of the null hypothesis |
| [maxvariables] | (approximate) maximal number of binary variables used when finding optimal design; if the sample space is too big this can be used to find approximate solutions to the optimization problem |
| [GS]           | flag indicating wheather the design should be group-sequential (constant stage two sample size upon continuation) |
"""
function SampleSpace( # unspecific variant
  n1range,
  nmax::TI;
  n2min::TI = 1, 
  maxnfact::TR = Inf, 
  nmincont::TI = 0, 
  maxvariables::TI = 500000, 
  GS::Bool = false
) where {TI<:Integer,TR<:Real}

  SampleSpace(
    convert(Vector{TI}, n1range), nmax, n2min, maxnfact, nmincont, maxvariables, GS
  )

end # external constructor (SampleSpace)


function SampleSpace(
  n1range::Vector{TI},
  nmax::TI,
  n2min::TI, 
  maxnfact::TR, 
  nmincont::TI, 
  maxvariables::TI, 
  GS::Bool
) where {TI<:Integer,TR<:Real}

  SampleSpace{TI,TR}(
      n1range, nmax, n2min, maxnfact, nmincont, maxvariables, GS
  )

end # external constructor (SampleSpace)


Base.size(::SampleSpace) = ()

Base.getindex(ss::SampleSpace, i) = ss

Base.show(io::IO, ss::SampleSpace) = print("SampleSpace")

"""
    interimsamplesizerange(ss::SampleSpace)

Return integer vector of valid ``n_1`` values.
"""
interimsamplesizerange(ss::SampleSpace) = ss.n1range

"""
    maxsamplesize(ss::SampleSpace)

Return maximal overal sample size as integer.
"""
maxsamplesize(ss::SampleSpace) = ss.nmax


"""
    possible(
      n1::TI2, ss::SampleSpace{TI,TR}
    ) where {TI<:Integer,TR<:Real,TI2<:Integer}

Return Bool indicating wheather `n1` is possible under `ss`.
"""
function possible(
  n1::TI2, ss::SampleSpace{TI,TR}
) where {TI<:Integer,TR<:Real,TI2<:Integer}

  return n1 in ss.n1range

end # possible

"""
    possible(
      n1::TI, n::TI, c::TR, ss::SampleSpace{TI2,TR2}
    ) where {TI<:Integer,TR<:Real,TI2<:Integer,TR2<:Real}

Return Bool indicating wheather the combination of `n1`, `n`, and `c` is 
possible under `ss`.
"""
function possible(
  n1::TI, n::TI, c::TR, ss::SampleSpace{TI2,TR2}
) where {TI<:Integer,TR<:Real,TI2<:Integer,TR2<:Real}

  res = n1 in ss.n1range # n1 must be possible
  res = n <= ss.nmax ? res : false # overall sample size constraint must not
                                     # be violated
  res = n1 <= n ? res : false # n1 cannot be larger than n
  res = n <= ss.maxnfact * n1 ? res : false # n cannot be too large in relation
                                            # to n1
  n2  = n - n1
  if (n2 < ss.n2min) & (c != Inf)
    # n2 too small (also affects "early stopping" for efficacy!)
    if (c == -Inf) & (n1 == n) & (n1 >= ss.nmincont) # fine, early stopping for efficacy
      nothing
    else
      res = false
    end
  end
  res = (n  < ss.nmincont) & (c != Inf) ? false : res # only stopping for futility may violate nmincount
  return res
end # possible


"""
    maxsamplesize(
      ss::SampleSpace{TI,TR}, n1::TI2
    ) where {TI<:Integer,TR<:Real,TI2<:Integer}

Return maximal sample size given `n1` as integer.
"""
function maxsamplesize(
  ss::SampleSpace{TI,TR}, n1::TI2
) where {TI<:Integer,TR<:Real,TI2<:Integer}

  possible(n1, ss)
  convert(TI, min(ss.nmax, floor(n1 * ss.maxnfact)))

end # maxsamplesize


"""
    isgroupsequential(ss::SampleSpace)

Indicate whether the sample space is restricted to group-sequential designs.
"""
isgroupsequential(ss::SampleSpace) = ss.GS


function getnvals(
  ss::SampleSpace{TI,TR}, n1::TI2
) where {TI<:Integer,TR<:Real,TI2<:Integer}

    nmax    = maxsamplesize(ss, n1)
    frac    = (nmax - n1 + 1) / sqrt(ss.maxvariables / n1)
    if frac > 1
        info(@sprintf("thinning nvals by factor %.3f", 1 / frac))
    else
        frac = 1
    end
    nvals   = convert(Vector{Int64}, round.(collect(n1:frac:nmax)))
    if !(n1 + ss.nmincont in nvals)
        push!(nvals, n1 + ss.nmincont)
    end
    if !((n1 + ss.n2min) in nvals)
        push!(nvals, n1 + ss.n2min)
    end
    if !(maxsamplesize(ss, n1) in nvals)
        push!(nvals, maxsamplesize(ss, n1))
    end
    for snval in ss.specialnvalues # ensure that all special nvals are contained!
        if !(snval in nvals) & (snval >= n1) & (snval <= nmax)
            push!(nvals, snval)
        end
    end
    return convert(Vector{Int64}, sort(nvals))

end # getnvals


function getcvals(
  ss::SampleSpace{TI,TR}, n1::TI2
) where {TI<:Integer,TR<:Real,TI2<:Integer}

    nmax        = maxsamplesize(ss, n1)
    frac        = nmax / sqrt(ss.maxvariables / n1)
    if frac > 1
        info(@sprintf("thinning cvals by factor %.3f", 1 / frac))
    else
        frac = 1
    end
    cvalsfinite = round.(collect(0:frac:(nmax - 1)))
    for scval in ss.specialcvalues # ensure that all special cvals are contained!
      if !(scval in cvalsfinite) & (scval >= n1) & (scval <= nmax)
          push!(cvalsfinite, scval)
      end
    end
    return cvalsfinite

end # getcvals
