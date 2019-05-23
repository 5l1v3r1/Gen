struct Normal <: Distribution{Float64} end

function broadcast_compatible_or_crash(args...)
    # This expression produces a DimensionMismatch exception if the shapes are
    # incompatible.  There seems to currently be no ready-made exception-free
    # way to check this, and I think it makes more sense to wait until that
    # capability exists in Julia proper than to re-implement it here.
    s = Base.Broadcast.broadcast_shape(map(size, args)...)
    true
end


"""
    normal(mu::Real, std::Real)

Samples a `Float64` value from a normal distribution.

    normal(mu::Array{Real, N}, std::Array{Real, N})

Samples an `Array{Float64, N}` where each element is independently normally
distributed.  This is equivalent to a multivariate normal with diagonal
covariance matrix, but its implementation is more efficient than that of the
more general `mvnormal` for this case.

The shapes of `mu` and `std` must be broadcast-compatible.  For methods such as
`logpdf(x, mu, std)` which involve an element of the support of the
distribution, the shapes of `x`, `mu` and `std` must be mutually
broadcast-compatible.

If `N == 0`, then distribution-related methods such as `logpdf`, `logpdf_grad`
and `random` return `Float64`s rather than properly returning `Array{Float64,
0}`s.  This is consistent with Julia's own inconsistency on the matter:

```jldoctest
julia> typeof(ones())
Array{Float64,0}

julia> typeof(ones() .* ones())
Float64
```
"""
const normal = Normal()

function logpdf(::Normal, x::Real, mu::Real, std::Real)
    var = std * std
    diff = x - mu
    -(diff * diff)/ (2.0 * var) - 0.5 * log(2.0 * pi * var)
end

function logpdf(::Normal,
                x::Array{T, N},
                mu::Array{U, N},
                std::Array{V, N}) where {T<:Real, U<:Real, V<:Real, N}
    broadcast_compatible_or_crash(x, mu, std)
    var = std .* std
    diff = x - y
    sum(-(diff .* diff) ./ (2.0 * var) - 0.5 * log.(2.0 * pi * var))
end

function logpdf_grad(::Normal, x::Real, mu::Real, std::Real)
    precision = 1. / (std * std)
    diff = mu - x
    deriv_x = diff * precision
    deriv_mu = -deriv_x
    deriv_std = -1. / std + (diff * diff) / (std * std * std)
    (deriv_x, deriv_mu, deriv_std)
end

function logpdf_grad(::Normal,
                     x::Array{T, N},
                     mu::Array{U, N},
                     std::Array{V, N}) where {T<:Real, U<:Real, V<:Real, N}
    broadcast_compatible_or_crash(x, mu, std)
    precision = 1.0 ./ (std .* std)
    diff = mu - x
    deriv_x = diff .* precision
    deriv_mu = -deriv_x
    deriv_std = -1.0 ./ std + (diff .* diff) / (std .* std .* std)
    (deriv_x, deriv_mu, deriv_std)
end

random(::Normal, mu::Real, std::Real) = mu + std * randn()

function random(::Normal,
                mu::Array{T, N},
                std::Array{U, N}) where {T<:Real, U<:Real, N}
    broadcast_compatible_or_crash(mu, std)
    mu + std .* randn(size(mu))
end

(::Normal)(mu, std) = random(Normal(), mu, std)

has_output_grad(::Normal) = true
has_argument_grads(::Normal) = (true, true)

export normal
