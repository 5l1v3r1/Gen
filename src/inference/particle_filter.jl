import Distributions

function effective_sample_size(log_normalized_weights::Vector{Float64})
    log_ess = -logsumexp(2. * log_normalized_weights)
    return exp(log_ess)
end

function normalize_weights(log_weights::Vector{Float64})
    log_total_weight = logsumexp(log_weights)
    log_normalized_weights = log_weights .- log_total_weight
    return (log_total_weight, log_normalized_weights)
end

#######################################
# building blocks for particle filter #
#######################################

mutable struct ParticleFilterState{U}
    traces::Vector{U}
    new_traces::Vector{U}
    log_weights::Vector{Float64}
    log_ml_est::Float64
    parents::Vector{Int}
end

"""
    traces = get_traces(state::ParticleFilterState)

Return the vector of traces in the current state, one for each particle.
"""
function get_traces(state::ParticleFilterState)
    state.traces

end

"""
    log_weights = get_log_weights(state::ParticleFilterState)

Return the vector of log weights for the current state, one for each particle.

The weights are not normalized, and are in log-space.
"""
function get_log_weights(state::ParticleFilterState)
    state.log_weights
end

"""
    estimate = log_ml_estimate(state::ParticleFilterState)

Return the particle filter's current estimate of the log marginal likelihood.
"""
function log_ml_estimate(state::ParticleFilterState)
    num_particles = length(state.traces)
    return state.log_ml_est + logsumexp(state.log_weights) - log(num_particles)
end

"""
    state = initialize_particle_filter(model::GenerativeFunction, model_args::Tuple,
        observations::Assignment proposal::GenerativeFunction, proposal_args::Tuple,
        num_particles::Int)

Initialize the state of a particle filter using a custom proposal for the initial latent state.
"""
function initialize_particle_filter(model::GenerativeFunction{T,U}, model_args::Tuple,
        observations::Assignment, proposal::GenerativeFunction, proposal_args::Tuple,
        num_particles::Int) where {T,U}
    traces = Vector{Any}(undef, num_particles)
    log_weights = Vector{Float64}(undef, num_particles)
    for i=1:num_particles
        (prop_choices, prop_weight, _) = Gen.propose(proposal, proposal_args)
        (traces[i], model_weight) = Gen.initialize(model, model_args, merge(observations, prop_choices))
        log_weights[i] = model_weight - prop_weight
    end
    ParticleFilterState{U}(traces, Vector{U}(undef, num_particles),
        log_weights, 0., collect(1:num_particles))
end

"""
    state = initialize_particle_filter(model::GenerativeFunction, model_args::Tuple,
        observations::Assignment, num_particles::Int)

Initialize the state of a particle filter, using the default proposal for the initial latent state.
"""
function initialize_particle_filter(model::GenerativeFunction{T,U}, model_args::Tuple,
        observations::Assignment, num_particles::Int) where {T,U}
    traces = Vector{Any}(undef, num_particles)
    log_weights = Vector{Float64}(undef, num_particles)
    for i=1:num_particles
        (traces[i], log_weights[i]) = Gen.initialize(model, model_args, observations)
    end
    ParticleFilterState{U}(traces, Vector{U}(undef, num_particles),
        log_weights, 0., collect(1:num_particles))
end

"""
    particle_filter_step!(state::ParticleFilterState, new_args::Tuple, argdiff,
        observations::Assignment, proposal::GenerativeFunction, proposal_args::Tuple)

Perform a particle filter update, where the model arguments are adjusted, new observations are added, and a custom proposal is used for new latent state.
"""
function particle_filter_step!(state::ParticleFilterState{U}, new_args::Tuple, argdiff,
        observations::Assignment, proposal::GenerativeFunction, proposal_args::Tuple) where {U}
    num_particles = length(state.traces)
    for i=1:num_particles
        (prop_choices, prop_weight, _) = Gen.propose(proposal, (state.traces[i], proposal_args...))
        constraints = merge(observations, prop_choices)
        (state.new_traces[i], up_weight, disc, _) = Gen.force_update(new_args, argdiff, state.traces[i], constraints)
        @assert isempty(disc)
        state.log_weights[i] += up_weight - prop_weight
    end
    
    # swap references
    tmp = state.traces
    state.traces = state.new_traces
    state.new_traces = tmp
    
    return nothing
end

"""
    particle_filter_step!(state::ParticleFilterState, new_args::Tuple, argdiff,
        observations::Assignment)

Perform a particle filter update, where the model arguments are adjusted, new observations are added, and the default proposal is used for new latent state.
"""
function particle_filter_step!(state::ParticleFilterState{U}, new_args::Tuple, argdiff,
        observations::Assignment) where {U}
    num_particles = length(state.traces)
    for i=1:num_particles
        (state.new_traces[i], increment, _) = Gen.extend(
            new_args, argdiff, state.traces[i], observations)
        state.log_weights[i] += increment
    end
    
    # swap references
    tmp = state.traces
    state.traces = state.new_traces
    state.new_traces = tmp
    
    return nothing
end

"""
    did_resample::Bool = maybe_resample!(state::ParticleFilterState;
        ess_threshold::Float64=length(state.traces)/2, verbose=false)

Do a resampling step if the effective sample size is below the given threshold.
"""
function maybe_resample!(state::ParticleFilterState{U};
                        ess_threshold::Real=length(state.traces)/2, verbose=false) where {U}
    num_particles = length(state.traces)
    (log_total_weight, log_normalized_weights) = normalize_weights(state.log_weights)
    ess = effective_sample_size(log_normalized_weights)
    do_resample = ess < ess_threshold
    if verbose
        println("effective sample size: $ess, doing resample: $do_resample")
    end
    if do_resample
        weights = exp.(log_normalized_weights)
        Distributions.rand!(Distributions.Categorical(weights / sum(weights)), state.parents)
        state.log_ml_est += log_total_weight - log(num_particles)
        for i=1:num_particles
            state.new_traces[i] = state.traces[state.parents[i]]
            state.log_weights[i] = 0.
        end
        
        # swap references
        tmp = state.traces
        state.traces = state.new_traces
        state.new_traces = tmp
    end
    return do_resample
end

export initialize_particle_filter, particle_filter_step!, maybe_resample!
export get_traces, get_log_weights, log_ml_estimate
