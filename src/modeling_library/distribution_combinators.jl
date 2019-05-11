# TODO: This does not allow a distribution to change type.
# (i.e., from Int to Float64).
using MacroTools

# A function call within a @dist body
# TODO: Improve to handle when args includes an Arg.
# Will require creating a new type of Arg.
dist_call(f, args) = f(args...)
dist_call(d::Distribution{T}, args) where T = DistWithArgs{T}(d, args)


#TODO: Make this actually compile a new type
macro dist(fnexpr)
  # First, pull out arguments and body
  fndef = splitdef(longdef(fnexpr))
  #
  # if !@capture(fnexpr, argexpr_ -> body_)
  #     error("@dist expression must be of the form @dist (args...) -> body")
  # end
  # arguments = (typeof(argexpr) == Symbol) ? (argexpr,) : argexpr.args # [] #argexpr

  arguments = fndef[:args]
  body = fndef[:body]

  name_to_index = Dict{Symbol, Int8}()
  for (i, arg) in enumerate(arguments)
      (argname, _, _, _) = splitarg(arg)
      name_to_index[argname] = i
  end

  function process_node(node)
      if typeof(node) == Symbol &&haskey(name_to_index, node)
          return :($(Arg(name_to_index[node])))
      end
      if @capture(node, f_(xs__))
          if f != :dist_call
              return :(Gen.dist_call($(f), ($(xs...),)))
          end
      end
      node
  end

  dwa_expr = MacroTools.postwalk(process_node, body)
  :($(esc(fndef[:name])) = compile_dist_with_args($(esc(dwa_expr)), Int8($(length(arguments)))))
end

# Represents a argument at a certain index
struct Arg
    i :: Int8
end

struct DistWithArgs{T}
    base :: Distribution{T}
    arglist # Contains Args and other values
end

struct CompiledDistWithArgs{T} <: Distribution{T}
    base :: Distribution{T}
    n_args :: Int8
    mapping :: Dict{Int8, Int8} # from 1:n_args to position in base arg list
    arg_grad_bools
    arglist
end

function compile_dist_with_args(d::DistWithArgs{T}, n::Int8)::CompiledDistWithArgs{T} where T
    mapping = Dict{Int8, Int8}()
    for (i, arg) in enumerate(d.arglist)
        if typeof(arg) == Arg
            mapping[arg.i] = Int8(i)
        end
    end
    base_arg_grads = has_argument_grads(d.base)
    arg_grad_bools = []
    for i=1:n
        push!(arg_grad_bools, !haskey(mapping, i) || base_arg_grads[mapping[i]])
    end
    CompiledDistWithArgs{T}(d.base, n, mapping, arg_grad_bools, d.arglist)
end

eval_arg(x::Any, args) = x
eval_arg(x::Arg, args) = args[x.i]

function logpdf(d::CompiledDistWithArgs{T}, x::T, args...) where T <: Real
    concrete_args = [eval_arg(arg, args) for arg in d.arglist]
    logpdf(d.base, x, concrete_args...)
end

function logpdf_grad(d::CompiledDistWithArgs{T}, x::T, args...) where T <: Real
    concrete_args = [eval_arg(arg, args) for arg in d.arglist]
    base_grad = logpdf_grad(d.base, x, concrete_args...)

    this_grad = [base_grad[1]]
    for j=1:d.n_args
        push!(this_grad, haskey(mapping, j) ? base_grad[mapping[j]] : 0.0)
    end
    this_grad
end

function random(d::CompiledDistWithArgs{T}, args...)::T where T <: Real
    concrete_args = [eval_arg(arg, args) for arg in d.arglist]
    random(d.base, concrete_args...)
end

is_discrete(d::CompiledDistWithArgs{T}) where T <: Real = is_discrete(d.base)

(d::CompiledDistWithArgs{T})(args...) where T <: Real = random(d, args...)

function has_output_grad(d::CompiledDistWithArgs{T}) where T <: Real
    has_output_grad(d.base)
end

function has_argument_grads(d::CompiledDistWithArgs{T}) where T <: Real
    d.arg_grad_bools
end


struct TranslatedByConstant{T} <: Distribution{T}
    a :: Real
    base :: Distribution{T}
end

function logpdf(d::TranslatedByConstant{T}, x::T, base_args...) where T <: Real
    logpdf(d.base, x-d.a, base_args...)
end

function logpdf_grad(d::TranslatedByConstant{T}, x::T, base_args...) where T <: Real
    logpdf_grad(d.base, x-d.a, base_args...)
end

function random(d::TranslatedByConstant{T}, base_args...)::T where T <: Real
    random(d.base, base_args...) + d.a
end

is_discrete(d::TranslatedByConstant{T}) where T <: Real = is_discrete(d.base)

(d::TranslatedByConstant{T})(base_args...) where T <: Real = random(d, base_args...)

function has_output_grad(d::TranslatedByConstant{T}) where T <: Real
    has_output_grad(d.base)
end

has_argument_grads(d::TranslatedByConstant{T}) where T <: Real = has_argument_grads(d.base)

Base.:+(b::DistWithArgs{T}, a::Real) where T <: Real = DistWithArgs(TranslatedByConstant(a, b.base), b.arglist)
Base.:+(a::Real, b::DistWithArgs{T}) where T <: Real = b + a
Base.:-(b::DistWithArgs{T}, a::Real) where T <: Real = b + (-a)

struct WithLocationArg{T} <: Distribution{T}
    base :: Distribution{T}
end

function logpdf(d::WithLocationArg{T}, x::T, loc::Real, base_args...) where T <: Real
    logpdf(d.base, x-loc, base_args...)
end

function logpdf_grad(d::WithLocationArg{T}, x::T, loc::Real, base_args...) where T <: Real
    base_grad = logpdf_grad(d.base, x-loc, base_args...)
    (base_grad[1], has_output_grad(d.base) ? (-1.0 * base_grad[1]) : nothing, base_grad[2:end]...)
end

function random(d::WithLocationArg{T}, loc::Real, base_args...)::T where T <: Real
    random(d.base, base_args...) + loc
end

is_discrete(d::WithLocationArg{T}) where T <: Real = is_discrete(d.base)

(d::WithLocationArg{T})(loc::Real, base_args...) where T <: Real = random(d, loc, base_args...)

function has_output_grad(d::WithLocationArg{T}) where T <: Real
    has_output_grad(d.base)
end

function has_argument_grads(d::WithLocationArg{T}) where T <: Real
    (has_output_grad(d.base), has_argument_grads(d.base)...)
end

Base.:+(b::DistWithArgs{T}, a::Arg) where T <: Real = DistWithArgs(WithLocationArg(b.base), (a, b.arglist...))
Base.:+(a::Arg, b::Distribution{T}) where T <: Real = b + a
# TODO: Make this work, using Var transformations.
#  But first, I should get things  working with simple vars.
# Base.:-(b::Distribution{T}, a::Real) where T <: Real = DistWithArgs(TranslatedByConstant(-a, b.base), b.arglist)


struct ScaledByConstant{T} <: Distribution{T}
    a :: Real
    base :: Distribution{T}
end

function logpdf(d::ScaledByConstant{T}, x::T, base_args...) where T <: Real
    if is_discrete(d.base)
        # TODO: is this unstable? If base distribution is discrete,
        # then x must be an exact multiple of an element of its support.
        logpdf(d.base, x/d.a, base_args...)
    else
        logpdf(d.base, x/d.a, base_args...) - log(d.a)
    end
end

function logpdf_grad(d::ScaledByConstant{T}, x::T, base_args...) where T <: Real
    if !is_discrete(d.base) && has_output_grad(d.base)
        grads = logpdf_grad(d.base, x/d.a, base_args...)
        (grads[1] / d.a, grads[2:end]...)
    else
        logpdf_grad(d.base, x/d.a, base_args...)
    end
end

function random(d::ScaledByConstant{T}, base_args...)::T where T <: Real
    random(d.base, base_args...) * d.a
end

is_discrete(d::ScaledByConstant{T}) where T <: Real = is_discrete(d.base)

(d::ScaledByConstant{T})(base_args...) where T <: Real = random(d, base_args...)

function has_output_grad(d::ScaledByConstant{T}) where T <: Real
    has_output_grad(d.base)
end

has_argument_grads(d::ScaledByConstant{T}) where T <: Real = has_argument_grads(d.base)

Base.:*(b::DistWithArgs{T}, a::Real) where T <: Real = DistWithArgs(ScaledByConstant(a, b.base), b.arglist)
Base.:*(a::Real, b::DistWithArgs{T}) where T <: Real = b * a
Base.:-(a::Real, b::DistWithArgs{T}) where T <: Real = a + (-1 * b) # DistWithArgs(TranslatedByConstant(a, ScaledByConstant(-1., b.base)), b.arglist)
Base.:-(b::DistWithArgs{T}, a::Real) where T <: Real = b + (-1 * a)
Base.:/(b::DistWithArgs{T}, a::Real) where T <: Real = 1.0/a * b # DistWithArgs(ScaledByConstant(1.0/a, b.base), b.arglist)

struct WithScaleArg{T} <: Distribution{T}
    base :: Distribution{T}
end

function logpdf(d::WithScaleArg{T}, x::T, scale::Real, base_args...) where T <: Real
    if is_discrete(d.base)
        # TODO: is this unstable? If base distribution is discrete,
        # then x must be an exact multiple of an element of its support.
        logpdf(d.base, x/scale, base_args...)
    else
        logpdf(d.base, x/scale, base_args...) - log(scale)
    end
end

function logpdf_grad(d::WithScaleArg{T}, x::T, scale::Real, base_args...) where T <: Real
    if !is_discrete(d.base) && has_output_grad(d.base)
        grads = logpdf_grad(d.base, x/scale, base_args...)
        (grads[1] / scale, -1. * grads[1] * x / (scale*scale), grads[2:end]...)
    else
        grads = logpdf_grad(d.base, x/scale, base_args...)
        (grads[1], nothing, grads[2:end])
    end
end

function random(d::WithScaleArg{T}, scale::Real, base_args...)::T where T <: Real
    random(d.base, base_args...) * scale
end

is_discrete(d::WithScaleArg{T}) where T <: Real = is_discrete(d.base)

(d::WithScaleArg{T})(scale::Real, base_args...) where T <: Real = random(d, scale, base_args...)

function has_output_grad(d::WithScaleArg{T}) where T <: Real
    has_output_grad(d.base)
end

has_argument_grads(d::WithScaleArg{T}) where T <: Real = (has_output_grad(d.base), has_argument_grads(d.base)...)

Base.:*(b::DistWithArgs{T}, a::Arg) where T <: Real = DistWithArgs(WithScaleArg(b.base), (a, b.arglist...))
Base.:*(a::Arg, b::DistWithArgs{T}) where T <: Real = b * a
Base.:-(a::Arg, b::DistWithArgs{T}) where T <: Real = -1 * b + a
Base.:-(b::DistWithArgs{T}, a::Arg) where T <: Real = -1 * (a - b)

# TODO: Add this later
# Base.:/(b::DistWithArgs{T}, a::Arg) where T <: Real = ScaledByConstant(1.0/a, b)

export @dist



# TODO: Gradient calculation is wrong if the argument appears more than once.
#  We should _sum_ contributions.

# The problem with f(a) is for derivative taking.
