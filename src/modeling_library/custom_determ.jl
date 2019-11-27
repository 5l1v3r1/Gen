#############################################################
# abstractions for constructing custom generative functions #
#############################################################

"""
    CustomDetermGFTrace{T,S} <: Trace

Trace type for custom deterministic generative function.
"""
struct CustomDetermGFTrace{T,S} <: Trace
    retval::T
    state::S
    args::Tuple
    gen_fn::Any
end

get_args(trace::CustomDetermGFTrace) = trace.args

get_retval(trace::CustomDetermGFTrace) = trace.retval

get_choices(trace::CustomDetermGFTrace) = EmptyChoiceMap()

get_score(trace::CustomDetermGFTrace) = 0.

project(trace::CustomDetermGFTrace, selection::Selection) = 0.

get_gen_fn(trace::CustomDetermGFTrace) = trace.gen_fn


"""
    CustomDetermGF{T,S} <: GenerativeFunction{T,CustomDetermGFTrace{T,S}} 

Abstract type for a custom deterministic generative function. 

A concrete subtype U <: CustomDetermGF must implement at a minimum the following functions:

- execute_determ(gen_fn::U, args)

- has_argument_grads(::U)

"""
abstract type CustomDetermGF{T,S} <: GenerativeFunction{T,CustomDetermGFTrace{T,S}} end

# default implementation, can be overridden
accepts_output_grad(::CustomDetermGF) = false

"""
    retval, state = execute_determ(gen_fn::CustomDetermGF, args)

Execute the generative function and return the return value and the state.
"""
function execute_determ end

"""
    state, retval, retdiff = update_determ(gen_fn::CustomDetermGF, state, args, argdiffs)

Update the arguments to the generative function and return new return value and state.
"""
function update_determ(gen_fn::CustomDetermGF{T,S}, state, args, argdiffs) where {T,S}
    # default implementation, can be overridden
    new_retval, new_state = execute_determ(gen_fn, args)
    retdiff = UnknownChange()
    (new_state, new_retval, retdiff)
end

"""
    arg_grads = gradient_determ(gen_fn::CustomDetermGF, state, args, retgrad) 

Return the gradient tuple with respect to the arguments.
"""
function gradient_determ(gen_fn::CustomDetermGF, state, args, retgrad)
    # default implementation, can be overridden
    map((_) -> nothing, args)
end

"""
    arg_grads = accumulate_param_gradients_determ!(
        gen_fn::CustomDetermGF, state, args, retgrad, scale_factor)
    
Increment gradient accumulators for parameters the gradient with respect to the
arguments, optionally scaled, and return the gradient with respect to the
arguments (not scaled).

Given the previous state and a gradient with respect to the return value \$∇_y
J\$ (`retgrad`), return the following gradient (`arg_grads`) with respect to
the arguments \$x\$:
```math
∇_x J
```
Also increment the gradient accumulators for the trainable parameters \$Θ\$ of
the function by:
```math
s * ∇_Θ J
```
where \$s\$ is `scale_factor`.
"""
function accumulate_param_gradients_determ!(
        gen_fn::CustomDetermGF, state, args, retgrad, scale_factor)
    # default implementation, can be overridden
    gradient_determ(gen_fn, state, args, retgrad)
end

function simulate(gen_fn::CustomDetermGF{T,S}, args::Tuple) where {T,S}
    retval, state = execute_determ(gen_fn, args)
    CustomDetermGFTrace{T,S}(retval, state, args, gen_fn)
end

function generate(gen_fn::CustomDetermGF{T,S}, args::Tuple, choices::ChoiceMap) where {T,S}
    if !isempty(choices)
        error("Deterministic generative function makes no random choices")
    end
    retval, state = execute_determ(gen_fn, args)
    trace = CustomDetermGFTrace{T,S}(retval, state, args, gen_fn)
    trace, 0.
end

function update(trace::CustomDetermGFTrace{T,S}, args::Tuple, argdiffs::Tuple, choices::ChoiceMap) where {T,S}
    if !isempty(choices)
        error("Deterministic generative function makes no random choices")
    end
    state, retval, retdiff = update_determ(trace.gen_fn, trace.state, args, argdiffs)
    new_trace = CustomDetermGFTrace{T,S}(retval, state, args, trace.gen_fn)
    (new_trace, 0., retdiff)
end

function regenerate(trace::CustomDetermGFTrace, args::Tuple, argdiffs::Tuple, selection::Selection)
    update(trace, args, argdiffs, EmptyChoiceMap())
end

function choice_gradients(trace::CustomDetermGFTrace, selection::Selection, retgrad)
    arg_grads = gradient_determ(trace.gen_fn, trace.state, trace.args, retgrad)
    (arg_grads, EmptyChoiceMap(), EmptyChoiceMap())
end

function accumulate_param_gradients!(trace::CustomDetermGFTrace, retgrad, scale_factor)
    accumulate_param_gradients_determ!(trace.gen_fn, trace.state, trace.args, retgrad, scale_factor)
end

export CustomDetermGF, CustomDetermGFTrace, execute_determ, update_determ, gradient_determ, accumulate_param_gradients_determ!
