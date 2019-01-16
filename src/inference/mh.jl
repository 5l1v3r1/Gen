"""
    (new_trace, accepted) = metropolis_hastings(trace, selection::AddressSet)

Perform a Metropolis-Hastings update that proposes new values for the selected addresses from the internal proposal (often using ancestral sampling).
"""
function metropolis_hastings(trace, selection::AddressSet)
    args = get_args(trace)
    (new_trace, weight) = free_update(args, noargdiff, trace, selection)
    if log(rand()) < weight
        # accept
        return (new_trace, true)
    else
        # reject
        return (trace, false)
    end
end


"""
    (new_trace, accepted) = metropolis_hastings(trace, proposal::GenerativeFunction, proposal_args::Tuple)

Perform a Metropolis-Hastings update that proposes new values for some subset of random choices in the given trace using the given proposal generative function.

The proposal generative function should take as its first argument the current trace of the model, and remaining arguments `proposal_args`.
If the proposal modifies addresses that determine the control flow in the model, values must be provided by the proposal for any addresses that are newly sampled by the model.
"""
function metropolis_hastings(trace, proposal::GenerativeFunction, proposal_args::Tuple)
    model_args = get_args(trace)
    proposal_args_forward = (trace, proposal_args...,)
    (fwd_assmt, fwd_weight, _) = propose(proposal, proposal_args_forward)
    (new_trace, weight, discard) = force_update(
        model_args, noargdiff, trace, fwd_assmt)
    proposal_args_backward = (new_trace, proposal_args...,)
    (bwd_weight, _) = assess(proposal, proposal_args_backward, discard)
    alpha = weight - fwd_weight + bwd_weight
    if log(rand()) < alpha
        # accept
        return (new_trace, true)
    else
        # reject
        return (trace, false)
    end
end

"""
    (new_trace, accepted) = metropolis_hastings(trace, proposal::GenerativeFunction, proposal_args::Tuple, involution::Function)

Perform a generalized Metropolis-Hastings update based on an involution (bijection that is its own inverse) on a space of assignments.

The `involution' Julia function has the following signature:

    (new_trace, bwd_assmt::Assignment, weight) = involution(trace, fwd_assmt::Assignment, fwd_ret, proposal_args::Tuple)

The generative function `proposal` is executed on arguments `(trace, proposal_args...)`, producing an assignment `fwd_assmt` and return value `fwd_ret`.
For each value of model arguments (contained in `trace`) and `proposal_args`, the `involution` function applies an involution that maps the tuple `(get_assmt(trace), fwd_assmt)` to the tuple `(get_assmt(new_trace), bwd_assmt)`.
Note that `fwd_ret` is a deterministic function of `fwd_assmt` and `proposal_args`.
When only discrete random choices are used, the `weight` must be equal to `get_score(new_trace) - get_score(trace)`.

**Including Continuous Random Choices**
When continuous random choices are used, the `weight` must include an additive term that is the determinant of the the Jacobian of the bijection on the continuous random choices that is obtained by currying the involution on the discrete random choices.
"""
function metropolis_hastings(trace, proposal::GenerativeFunction,
                    proposal_args::Tuple, involution::Function)
    (fwd_assmt, fwd_score, fwd_ret) = propose(proposal, (trace, proposal_args...,))
    (new_trace, bwd_assmt, weight) = involution(trace, fwd_assmt, fwd_ret, proposal_args)
    (bwd_score, _) = assess(proposal, (new_trace, proposal_args...), bwd_assmt)
    if log(rand()) < weight - fwd_score + bwd_score
        # accept
        (new_trace, true)
    else
        # reject
        (trace, false)
    end
end

"""
    (new_trace, accepted) = mh(trace, selection::AddressSet)
    (new_trace, accepted) = mh(trace, proposal::GenerativeFunction, proposal_args::Tuple)
    (new_trace, accepted) = mh(trace, proposal::GenerativeFunction, proposal_args::Tuple, involution::Function)

Alias for [`metropolis_hastings`](@ref). Perform a Metropolis-Hastings update on the given trace.
"""
const mh = metropolis_hastings

export metropolis_hastings, mh
