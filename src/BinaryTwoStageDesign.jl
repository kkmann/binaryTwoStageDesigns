abstract AbstractBinaryTwoStageDesign


# these two enable array broadcasting of all methods!
Base.size(::AbstractBinaryTwoStageDesign) = ()
Base.getindex(design::AbstractBinaryTwoStageDesign, i) = design


immutable BinaryTwoStageDesign{T1<:Integer, T2<:Real, PType<:Parameters} <: AbstractBinaryTwoStageDesign
    n::Vector{T1}
    c::Vector{T2} # rejected if x1 + x2 > c(x1), must allow real to hold Infinity
    params::PType
    function BinaryTwoStageDesign(n, c)
        any(n .< (length(n) - 1)) ? throw(InexactError()) : nothing
        length(n) != length(c) ? throw(InexactError()) : nothing
        new(n, c, NoParameters())
    end
    function BinaryTwoStageDesign(n, c, params)
        any(n .< (length(n) - 1)) ? throw(InexactError()) : nothing
        length(n) != length(c) ? throw(InexactError()) : nothing
        new(n, c, params)
    end
end # BinaryTwoStageDesign
BinaryTwoStageDesign{T1<:Integer, T2<:Real}(
    n::Vector{T1},
    c::Vector{T2}
) = BinaryTwoStageDesign{T1, T2, NoParameters}(n, c)
BinaryTwoStageDesign{T1<:Integer, T2<:Real, PType<:Parameters}(
    n::Vector{T1},
    c::Vector{T2},
    params::PType
) = BinaryTwoStageDesign{T1, T2, PType}(n, c, params)


show(io::IO, object::AbstractBinaryTwoStageDesign) = println("Binary two-stage design")


convert(::Type{DataFrames.DataFrame}, design::AbstractBinaryTwoStageDesign) =
    DataFrames.DataFrame(
        x1 = 0:interimsamplesize(design),
        n  = samplesize(design),
        c  = criticalvalue(design)
    )


interimsamplesize(design::AbstractBinaryTwoStageDesign) = length(design.n) - 1
parameters(design::AbstractBinaryTwoStageDesign) = design.params

samplesize(design::AbstractBinaryTwoStageDesign) = design.n
samplesize{T<:Integer}(design::AbstractBinaryTwoStageDesign, x1::T) =
    (checkx1(x1, design); design.n[x1 + 1])


criticalvalue(design::AbstractBinaryTwoStageDesign) = design.c
criticalvalue{T<:Integer}(design::AbstractBinaryTwoStageDesign, x1::T) =
    (checkx1(x1, design); design.c[x1 + 1])


function pdf{T1<:Integer, T2<:Real}(
    design::AbstractBinaryTwoStageDesign,
    x1::T1, x2::T1, p::T2
)
    checkp(p)
    try
        checkx1x2(x1, x2, design)
    catch
        return 0.0
    end
    n1 = interimsamplesize(design)
    n  = samplesize(design, x1)
    try
        return p^(x1 + x2)*(1 - p)^(n - x1 - x2)*binomial(n1, x1)*binomial(n - n1, x2) # is 0 if impossible
    catch
        return p^(x1 + x2)*(1 - p)^(n - x1 - x2)*binomial(BigInt(n1), BigInt(x1))*binomial(BigInt(n - n1), BigInt(x2)) # is 0 if impossible
    end

end


function power{T1<:Integer, T2<:Real}(
    design::AbstractBinaryTwoStageDesign, x1::T1, p::T2
)
    checkp(p)
    checkx1(x1, design)
    return _cpr(
        x1,
        interimsamplesize(design),
        samplesize(design, x1),
        criticalvalue(design, x1),
        p
    )
end
function power{T<:Real}(design::AbstractBinaryTwoStageDesign, p::T)
    checkp(p)
    n1      = interimsamplesize(design)
    X1      = Distributions.Binomial(n1, p) # stage one responses
    x1range = collect(0:n1)
    return vecdot(Distributions.pdf(X1, x1range), power.(design, x1range, p))
end


function test{T<:Integer}(design::AbstractBinaryTwoStageDesign, x1::T, x2::T)::Bool
    checkx1x2(x1, x2, design)
    return x1 + x2 > criticalvalue(design, x1) ? true : false
end


function simulate{T1<:Integer, T2<:Real}(design::AbstractBinaryTwoStageDesign, p::T2, nsim::T1)
    x2    = SharedArray(Int, nsim)
    n     = SharedArray(Int, nsim)
    c     = SharedArray(Float64, nsim)
    rej   = SharedArray(Bool, nsim)
    n1    = interimsamplesize(design)
    rv_x1 = Distributions.Binomial(n1, p)
    x1    = SharedArray(Int, nsim)
    @sync @parallel for i in 1:nsim
        x1[i]  = rand(rv_x1)
        n2     = samplesize(design, x1[i]) - n1
        n[i]   = n2 + n1
        c[i]   = criticalvalue(design, x1[i])
        x2[i]  = rand(Distributions.Binomial(n2, p))
        rej[i] = test(design, x1[i], x2[i])
    end
    return DataFrames.DataFrame(
        x1 = convert(Vector{Int}, x1),
        n  = convert(Vector{Int}, n),
        c  = convert(Vector{Float64}, c),
        x2 = convert(Vector{Int}, x2),
        rejectedH0 = convert(Vector{Bool}, rej)
    )
end


score(design::AbstractBinaryTwoStageDesign, params::Parameters)::Real = error("not implemented")
score(design::AbstractBinaryTwoStageDesign)::Real = score(design, parameters(design))



# utility functions
function checkx1{T<:Integer}(x1::T, design::AbstractBinaryTwoStageDesign)
    x1 < 0 ? throw(InexactError("x1 must be non-negative")) : nothing
    x1 > interimsamplesize(design) ? throw(InexactError("x1 smaller or equal to n1")) : nothing
end

function checkx1x2{T<:Integer}(x1::T, x2::T, design::AbstractBinaryTwoStageDesign)
    checkx1(x1, design)
    x2 < 0 ? throw(InexactError("x2 must be non-negative")) : nothing
    n1 = interimsamplesize(design)
    n2 = samplesize(design, x1) - n1
    x2 > n2 ? throw(InexactError("x2 must be smaller or equal to n2")) : nothing
end

checkp{T<:Real}(p::T) = (0.0 > p) & (p > 1.0) ? throw(InexactError("p must be in [0, 1]")) : nothing

function _cpr(x1, n1, n, c, p)
    # conditional probability to reject
    if x1 > c
        return(1.0)
    end
    if n - n1 + x1 <= c
        return(0.0)
    end
    return 1 - Distributions.cdf(Distributions.Binomial(n - n1, p), convert(Int64, c - x1))
end
