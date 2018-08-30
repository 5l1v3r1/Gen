using Gen
import Random

#########
# model #
#########

@gen function datum(x::Float64, @ad(inlier_std), @ad(outlier_std), @ad(slope), @ad(intercept))
    is_outlier = @addr(bernoulli(0.5), :z)
    std = is_outlier ? inlier_std : outlier_std
    y = @addr(normal(x * slope + intercept, std), :y)
    return y
end

data = plate(datum)

@gen function model(xs::Vector{Float64})
    n = length(xs)
    inlier_std = exp(@addr(normal(0, 2), :inlier_std))
    outlier_std = exp(@addr(normal(0, 2), :outlier_std))
    slope = @addr(normal(0, 2), :slope)
    intercept = @addr(normal(0, 2), :intercept)
    if all([@change(addr) == NoChange() for addr in [:slope, :intercept, :inlier_std, :outlier_std]])
        change = NoChange()
    else
        change = nothing
    end
    ys = @addr(data(xs, fill(inlier_std, n), fill(outlier_std, n), fill(slope, n), fill(intercept, n)), :data, change)
    return ys
end

#######################
# inference operators #
#######################

@gen function mala_proposal(values, gradients, tau, addrs)
    for addr in addrs
        @addr(normal(values[addr] + tau * gradients[addr], sqrt(2*tau)), addr)
    end
end

function mala_move(trace, tau::Float64, addrs)
    selection = DynamicAddressSet()
    for addr in addrs
        Gen.push_leaf_node!(selection, addr)
    end
    (_, values, gradients) = backprop_trace(model, trace, selection, nothing)
    forward_trace = simulate(mala_proposal, (values, gradients, tau, addrs))
    forward_score = get_call_record(forward_trace).score
    constraints = get_choices(forward_trace)
    model_args = get_call_record(trace).args
    (new_trace, weight, discard) = update(
        model, model_args, NoChange(), trace, constraints)
    backward_trace = assess(mala_proposal, (values, gradients, tau, addrs), discard)
    backward_score = get_call_record(backward_trace).score
    alpha = weight - forward_score + backward_score
    if log(rand()) < alpha
        # accept
        return new_trace
    else
        # reject
        return trace
    end
end

@gen function is_outlier_proposal(prev, i::Int)
    prev_z = prev[:data => i => :z]
    @addr(bernoulli(prev_z ? 0.0 : 1.0), :data => i => :z)
end

@gen function observer(ys::Vector{Float64})
    for (i, y) in enumerate(ys)
        @addr(dirac(y), :data => i => :y)
    end
end

Gen.load_generated_functions()

#####################
# generate data set #
#####################

Random.seed!(1)

prob_outlier = 0.5
true_inlier_noise = 0.5
true_outlier_noise = 5.0
true_slope = -1
true_intercept = 2
xs = collect(range(-5, stop=5, length=200))
ys = Float64[]
for (i, x) in enumerate(xs)
    if rand() < prob_outlier
        y = true_slope * x + true_intercept + randn() * true_inlier_noise
    else
        y = true_slope * x + true_intercept + randn() * true_outlier_noise
    end
    push!(ys, y)
end

##################
# run experiment #
##################


function do_inference(n)
    observations = get_choices(simulate(observer, (ys,)))
    
    # initial trace
    (trace, _) = generate(model, (xs,), observations)
    
    for i=1:n
        trace = mala_move(trace, 0.0001, [:slope, :intercept, :inlier_std, :outlier_std])
    
        # step on the outliers
        for j=1:length(xs)
            trace = mh(model, is_outlier_proposal, (j,), trace)
        end
    
        score = get_call_record(trace).score
    
        # print
        choices = get_choices(trace)
        slope = choices[:slope]
        intercept = choices[:intercept]
        inlier_std = choices[:inlier_std]
        outlier_std = choices[:outlier_std]
        println("score: $score, slope: $slope, intercept: $intercept, inlier_std: $inlier_std, outlier_std: $outlier_std")
    end
end

@time do_inference(100)
@time do_inference(100)
