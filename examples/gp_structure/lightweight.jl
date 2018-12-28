include("shared.jl")

@gen function covariance_prior(cur::Int)
    node_type = @addr(categorical(node_dist), (cur, :type))

    if node_type == CONSTANT
        param = @addr(uniform_continuous(0, 1), (cur, :param))
        node = Constant(param)

    # linear kernel
    elseif node_type == LINEAR
        param = @addr(uniform_continuous(0, 1), (cur, :param))
        node = Linear(param)

    # squared exponential kernel
    elseif node_type == SQUARED_EXP
        length_scale= @addr(uniform_continuous(0, 1), (cur, :length_scale))
        node = SquaredExponential(length_scale)

    # periodic kernel
    elseif node_type == PERIODIC
        scale = @addr(uniform_continuous(0, 1), (cur, :scale))
        period = @addr(uniform_continuous(0, 1), (cur, :period))
        node = Periodic(scale, period)

    # plus combinator
    elseif node_type == PLUS
        child1 = get_child(cur, 1, max_branch)
        child2 = get_child(cur, 2, max_branch)
        left = @splice(covariance_prior(child1))
        right = @splice(covariance_prior(child2))
        node = Plus(left, right)

    # times combinator
    elseif node_type == TIMES
        child1 = get_child(cur, 1, max_branch)
        child2 = get_child(cur, 2, max_branch)
        left = @splice(covariance_prior(child1))
        right = @splice(covariance_prior(child2))
        node = Times(left, right)

    # unknown node type
    else
        error("Unknown node type: $node_type")
    end

    return node
end

@gen function model(xs::Vector{Float64})
    n = length(xs)

    # sample covariance function
    covariance_fn::Node = @addr(covariance_prior(1), :tree)

    # sample diagonal noise
    noise = @addr(gamma(1, 1), :noise) + 0.01

    # compute covariance matrix
    cov_matrix = compute_cov_matrix_vectorized(covariance_fn, noise, xs)

    # sample from multivariate normal   
    @addr(mvnormal(zeros(n), cov_matrix), :ys)

    return covariance_fn
end

@gen function noise_proposal(prev_trace)
    @addr(gamma(1, 1), :noise)
end

@gen function subtree_proposal(prev_trace)
    prev_subtree_node::Node = get_retval(prev_trace)
    (subtree_idx::Int, depth::Int) = @addr(pick_random_node(prev_subtree_node, 1, 0), :choose_subtree_root)
    new_subtree_node::Node = @addr(covariance_prior(subtree_idx), :subtree)
    (subtree_idx, depth, new_subtree_node)
end

function subtree_involution(trace, fwd_assmt::Assignment, fwd_ret::Tuple, proposal_args::Tuple)
    (subtree_idx, subtree_depth, new_subtree_node) = fwd_ret
    model_args = get_args(trace)

    # populate constraints with proposed subtree
    constraints = DynamicAssignment()
    set_subassmt!(constraints, :tree, get_subassmt(fwd_assmt, :subtree))

    # obtain new trace and discard, which contains the previous subtree
    (new_trace, weight, discard, _) = force_update(model_args, noargdiff, trace, constraints)

    # populate backward assignment with choice of root
    bwd_assmt = DynamicAssignment()
    set_subassmt!(bwd_assmt, :choose_subtree_root => :recurse_left,
        get_subassmt(fwd_assmt, :choose_subtree_root => :recurse_left))
    for depth=0:subtree_depth-1
        bwd_assmt[:choose_subtree_root => :done => depth] = false
    end
    if !isa(new_subtree_node, LeafNode)
        bwd_assmt[:choose_subtree_root => :done => subtree_depth] = true
    end

    # populate backward assignment with the previous subtree
    set_subassmt!(bwd_assmt, :subtree, get_subassmt(discard, :tree))

    (new_trace, bwd_assmt, weight)
end

function inference(xs::Vector{Float64}, ys::Vector{Float64}, num_iters::Int, callback)

    # observed data
    constraints = DynamicAssignment()
    constraints[:ys] = ys

    # generate initial trace consistent with observed data
    (trace, _) = initialize(model, (xs,), constraints)

    # do MCMC
    local covariance_fn::Node
    local noise::Float64
    for iter=1:num_iters

        covariance_fn = get_retval(trace)
        noise = get_assmt(trace)[:noise]
        callback(covariance_fn, noise)

        # do MH move on the subtree
        (trace, _) = general_mh(trace, subtree_proposal, (), subtree_involution)

        # do MH move on the top-level white noise
        (trace, _) = custom_mh(trace, noise_proposal, ())
    end
    (covariance_fn, noise)
end

function experiment()

    # load and rescale the airline dataset
    (xs, ys) = get_airline_dataset()
    xs_train = xs[1:100]
    ys_train = ys[1:100]
    xs_test = xs[101:end]
    ys_test = ys[101:end]

    # set seed
    Random.seed!(0)

    # print MSE and predictive log likelihood on test data
    callback = (covariance_fn, noise) -> begin
        pred_ll = predictive_ll(covariance_fn, noise, xs_train, ys_train, xs_test, ys_test)
        mse = compute_mse(covariance_fn, noise, xs_train, ys_train, xs_test, ys_test)
        println("mse: $mse, predictive log likelihood: $pred_ll")
    end

    # do inference, time it
    @time (covariance_fn, noise) = inference(xs_train, ys_train, 1000, callback)

    # sample predictions
    pred_ys = predict_ys(covariance_fn, noise, xs_train, ys_train, xs_test)
end

experiment()
