mutable struct GFExtendState
    prev_trace::GFTrace
    trace::GFTrace
    args_change::Any
    constraints::Any
    score::Float64
    weight::Float64
    visitor::AddressVisitor
    params::Dict{Symbol,Any}
    retchange::ChangeInfo
    callee_output_changes::HomogenousTrie{Any,ChangeInfo}
end

function GFExtendState(args_change, prev_trace, constraints, params)
    visitor = AddressVisitor()
    GFExtendState(prev_trace, GFTrace(), args_change, constraints, 0., 0.,
        visitor, params, nothing, HomogenousTrie{Any,ChangeInfo}())
end

get_args_change(state::GFExtendState) = state.args_change

function set_ret_change!(state::GFExtendState, value)
    if state.retchange === nothing
        state.retchange = value
    else
        lightweight_retchange_already_set_err()
    end
end

function get_addr_change(state::GFExtendState, addr)
    get_leaf_node(state.callee_output_changes, addr)
end

function extend_no_change_err(addr)
    error("Attempted to change value of random choice at $addr during extend")
end

function addr(state::GFExtendState, dist::Distribution{T}, args, addr) where {T}
    visit!(state.visitor, addr)
    has_previous = has_primitive_call(state.prev_trace, addr)
    constrained = has_leaf_node(state.constraints, addr)
    if has_previous && constrained
        extend_no_change_err(addr)
    end
    lightweight_check_no_internal_node(state.constraints, addr)
    local retval::T
    local call::CallRecord
    if has_previous
        call = get_primitive_call(state.prev_trace, addr)
        if call.args != args
            extend_no_change_err(addr)
        end
        retval = call.retval
        score = call.score
    elseif constrained
        retval = get_leaf_node(state.constraints, addr)
        score = logpdf(dist, retval, args...)
        state.weight += score
        call = CallRecord(score, retval, args)
    else
        retval = random(dist, args...)
        score = logpdf(dist, retval, args...)
        call = CallRecord(score, retval, args)
    end
    state.trace = assoc_primitive_call(state.trace, addr, call)
    state.score += score
    if constrained && has_previous
        # there was a change and this was the previous value
        retchange = Some(prev_call.retval)
    elseif has_previous
        retchange = NoChange()
    else
        # retchange is null, because the address is new
        retchange = nothing
    end
    set_leaf_node!(state.callee_output_changes, addr, retchange)
    retval 
end

function addr(state::GFExtendState, gen::Generator{T}, args, addr, args_change) where {T}
    visit!(state.visitor, addr)
    lightweight_check_no_leaf_node(state.constraints, addr)
    if has_internal_node(state.constraints, addr)
        constraints = get_internal_node(state.constraints, addr)
    else
        constraints = EmptyAssignment()
    end
    if has_subtrace(state.prev_trace, addr)
        prev_trace = get_subtrace(state.prev_trace, addr)
        (trace, weight, retchange) = extend(gen, args, args_change, prev_trace, constraints)
        set_leaf_node!(state.callee_output_changes, addr, retchange)
    else
        (trace, weight) = generate(gen, args, constraints)
    end
    call::CallRecord = get_call_record(trace)
    retval::T = call.retval
    state.trace = assoc_subtrace(state.trace, addr, trace)
    state.score += call.score
    state.weight += weight
    retval 
end

function splice(state::GFExtendState, gen::GenFunction, args::Tuple)
    exec(gf, state, args)
end

function extend(gf::GenFunction, args, args_change, trace::GFTrace, constraints)
    state = GFExtendState(args_change, trace, constraints, gf.params)
    retval = exec(gf, state, args)
    call = CallRecord(state.score, retval, args)
    state.trace.call = call
    (state.trace, state.weight, state.retchange)
end
