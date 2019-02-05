@testset "map combinator" begin
    
    @gen (grad) function foo((grad)(x::Float64), (grad)(y::Float64))
        @param std::Float64
        z = @addr(normal(x + y, std), :z)
        @diff begin
            zdiff = @choicediff(:z)
            @retdiff(isnodiff(zdiff) ? NoRetDiff() : DefaultRetDiff())
        end
        return z
    end

    set_param!(foo, :std, 1.)

    bar = Map(foo)
    xs = [1.0, 2.0, 3.0, 4.0]
    ys = [3.0, 4.0, 5.0, 6.0]

    @testset "generate" begin
        z1, z2 = 1.1, 2.2
        constraints = choicemap()
        constraints[1 => :z] = z1
        (trace, weight) = generate(bar, (xs[1:2], ys[1:2]), constraints)
        assignment = get_choices(trace)
        @test assignment[1 => :z] == z1
        z2 = assignment[2 => :z]
        @test isapprox(weight, logpdf(normal, z1, 4., 1.))
    end

    @testset "propose" begin
        (choices, weight) = propose(bar, (xs[1:2], ys[1:2]))
        z1 = choices[1 => :z]
        z2 = choices[2 => :z]
        expected_weight = logpdf(normal, z1, 4., 1.) + logpdf(normal, z2, 6., 1.)
        @test isapprox(weight, expected_weight)
    end

    @testset "assess" begin
        z1, z2 = 1.1, 2.2
        constraints = choicemap()
        constraints[1 => :z] = z1
        constraints[2 => :z] = z2
        (weight, retval) = assess(bar, (xs[1:2], ys[1:2]), constraints)
        @test length(retval) == 2
        expected_weight = logpdf(normal, z1, 4., 1.) + logpdf(normal, z2, 6., 1.)
        @test isapprox(weight, expected_weight)
    end

    @testset "update" begin
        z1, z2 = 1.1, 2.2

        function get_initial_trace()
            constraints = choicemap()
            constraints[1 => :z] = z1
            constraints[2 => :z] = z2
            (trace, _) = generate(bar, (xs[1:2], ys[1:2]), constraints)
            trace
        end

        # unknownargdiff, increasing length from 2 to 3 and change 2
        trace = get_initial_trace()
        z2_new = 3.3
        z3_new = 4.4
        constraints = choicemap()
        constraints[2 => :z] = z2_new
        constraints[3 => :z] = z3_new
        (trace, weight, retdiff, discard) = update(trace,
            (xs[1:3], ys[1:3]), unknownargdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:3], ys[1:3])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2_new
        @test choices[3 => :z] == z3_new
        @test discard[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2_new, 6., 1.)
            + logpdf(normal, z3_new, 8., 1.))
        @test isapprox(get_score(trace), expected_score)
        expected_weight = (logpdf(normal, z3_new, 8., 1.)
            + logpdf(normal, z2_new, 6., 1.)
            - logpdf(normal, z2, 6., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 3
        @test retval[1] == z1
        @test retval[2] == z2_new
        @test retval[3] == z3_new
        @test isa(retdiff, VectorCustomRetDiff)
        @test !haskey(retdiff, 1) # no diff
        @test retdiff[2] == DefaultRetDiff() # retval changed
        @test !haskey(retdiff, 3) # new, not retained
        @test !isnodiff(retdiff)

        # unknownargdiff, decreasing length from 2 to 1 and change 1
        trace = get_initial_trace()
        z1_new = 3.3
        constraints = choicemap()
        constraints[1 => :z] = z1_new
        (trace, weight, retdiff, discard) = update(trace,
            (xs[1:1], ys[1:1]), unknownargdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:1], ys[1:1])
        @test !has_value(choices, 2 => :z)
        @test !has_value(choices, 3 => :z)
        @test choices[1 => :z] == z1_new
        @test discard[1 => :z] == z1
        @test discard[2 => :z] == z2
        @test isapprox(get_score(trace), logpdf(normal, z1_new, 4., 1.))
        expected_weight = (logpdf(normal, z1_new, 4., 1.)
            - logpdf(normal, z1, 4., 1.)
            - logpdf(normal, z2, 6., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 1
        @test retval[1] == z1_new
        @test isa(retdiff, VectorCustomRetDiff)
        @test retdiff[1] == DefaultRetDiff() # retval changed
        @test !haskey(retdiff, 2) # removed, not retained
        @test !isnodiff(retdiff)

        # noargdiff, change nothing
        trace = get_initial_trace()
        constraints = choicemap()
        (trace, weight, retdiff, discard) = update(trace,
            (xs[1:2], ys[1:2]), noargdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        @test isempty(discard)
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        @test isapprox(weight, 0.)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test isa(retdiff, NoRetDiff)
        @test isnodiff(retdiff)

        # noargdiff, change 2
        trace = get_initial_trace()
        z2_new = 3.3
        constraints = choicemap()
        constraints[2 => :z] = z2_new
        (trace, weight, retdiff, discard) = update(trace,
            (xs[1:2], ys[1:2]), noargdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2_new
        @test discard[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2_new, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        expected_weight = (logpdf(normal, z2_new, 6., 1.)
            - logpdf(normal, z2, 6., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2_new
        @test isa(retdiff, VectorCustomRetDiff)
        @test !haskey(retdiff, 1) # no diff
        @test retdiff[2] == DefaultRetDiff() # retval changed
        @test !isnodiff(retdiff)

        # custom argdiff, no constraints
        trace = get_initial_trace()
        xs_new = copy(xs)
        xs_new[1] = -1. # change from 1 to -1
        argdiff = MapCustomArgDiff(Dict(1 => unknownargdiff))
        constraints = choicemap()
        (trace, weight, retdiff, discard) = update(trace,
            (xs_new[1:2], ys[1:2]), argdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs_new[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        @test isempty(discard)
        expected_score = (logpdf(normal, z1, 2., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        expected_weight = (logpdf(normal, z1, 2., 1.)
            - logpdf(normal, z1, 4., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test retdiff == NoRetDiff()
        @test isnodiff(retdiff)
    end

    @testset "regenerate" begin
        z1, z2 = 1.1, 2.2

        function get_initial_trace()
            constraints = choicemap()
            constraints[1 => :z] = z1
            constraints[2 => :z] = z2
            (trace, _) = generate(bar, (xs[1:2], ys[1:2]), constraints)
            trace
        end

        # unknownargdiff, increasing length from 2 to 3 and change 2
        trace = get_initial_trace()
        selection = select(2 => :z)
        (trace, weight, retdiff) = regenerate(trace,
            (xs[1:3], ys[1:3]), unknownargdiff, selection)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:3], ys[1:3])
        @test choices[1 => :z] == z1
        z2_new = choices[2 => :z]
        z3_new = choices[3 => :z]
        score = get_score(trace)
        @test isapprox(score, (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2_new, 6., 1.)
            + logpdf(normal, z3_new, 8., 1.)))
        @test isapprox(weight, 0.)

        # unknownargdiff, decreasing length from 2 to 1 and change 1
        trace = get_initial_trace()
        selection = select(1 => :z)
        (trace, weight, retdiff) = regenerate(trace,
            (xs[1:1], ys[1:1]), unknownargdiff, selection)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:1], ys[1:1])
        @test !has_value(choices, 2 => :z)
        @test !has_value(choices, 3 => :z)
        z1_new = choices[1 => :z]
        @test isapprox(get_score(trace), logpdf(normal, z1_new, 4., 1.))
        @test isapprox(weight, 0.)

        # noargdiff, change nothing
        trace = get_initial_trace()
        selection = EmptyAddressSet()
        (trace, weight, retdiff) = regenerate(trace,
            (xs[1:2], ys[1:2]), noargdiff, selection)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        @test isapprox(weight, 0.)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test isa(retdiff, NoRetDiff)
        @test isnodiff(retdiff)

        # noargdiff, change 2
        trace = get_initial_trace()
        selection = select(2 => :z)
        (trace, weight, retdiff) = regenerate(trace,
            (xs[1:2], ys[1:2]), noargdiff, selection)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        z2_new = choices[2 => :z]
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2_new, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        @test isapprox(weight, 0.)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2_new
        @test isa(retdiff, VectorCustomRetDiff)
        @test !haskey(retdiff, 1) # no diff
        @test retdiff[2] == DefaultRetDiff() # retval changed
        @test !isnodiff(retdiff)

        # custom argdiff, no selection
        trace = get_initial_trace()
        xs_new = copy(xs)
        xs_new[1] = -1. # change from 1 to -1
        argdiff = MapCustomArgDiff(Dict(1 => unknownargdiff))
        selection = EmptyAddressSet()
        (trace, weight, retdiff) = regenerate(trace,
            (xs_new[1:2], ys[1:2]), argdiff, selection)
        choices = get_choices(trace)
        @test get_args(trace) == (xs_new[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 2., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        expected_weight = (logpdf(normal, z1, 2., 1.)
            - logpdf(normal, z1, 4., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test retdiff == NoRetDiff()
        @test isnodiff(retdiff)
    end

    @testset "extend" begin
        z1, z2 = 1.1, 2.2

        function get_initial_trace()
            constraints = choicemap()
            constraints[1 => :z] = z1
            constraints[2 => :z] = z2
            (trace, _) = generate(bar, (xs[1:2], ys[1:2]), constraints)
            trace
        end

        # unknownargdiff, increasing length from 2 to 4; constrain 4 and let 3
        # be generated from prior
        trace = get_initial_trace()
        z4 = 4.4
        constraints = choicemap()
        constraints[4 => :z] = z4
        (trace, weight, retdiff) = extend(trace,
            (xs[1:4], ys[1:4]), unknownargdiff, constraints)
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:4], ys[1:4])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        @test choices[4 => :z] == z4
        z3 = choices[3 => :z]
        score = get_score(trace)
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2, 6., 1.)
            + logpdf(normal, z3, 8., 1.)
            + logpdf(normal, z4, 10., 1))
        @test isapprox(score, expected_score)
        @test isapprox(weight, logpdf(normal, z4 , 10., 1.))

        # noargdiff, change nothing
        trace = get_initial_trace()
        (trace, weight, retdiff) = extend(trace,
            (xs[1:2], ys[1:2]), noargdiff, EmptyChoiceMap())
        choices = get_choices(trace)
        @test get_args(trace) == (xs[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 4., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        @test isapprox(weight, 0.)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test isa(retdiff, NoRetDiff)
        @test isnodiff(retdiff)

        # custom argdiff, no selection
        trace = get_initial_trace()
        xs_new = copy(xs)
        xs_new[1] = -1. # change from 1 to -1
        argdiff = MapCustomArgDiff(Dict(1 => unknownargdiff))
        (trace, weight, retdiff) = extend(trace,
            (xs_new[1:2], ys[1:2]), argdiff, EmptyChoiceMap())
        choices = get_choices(trace)
        @test get_args(trace) == (xs_new[1:2], ys[1:2])
        @test choices[1 => :z] == z1
        @test choices[2 => :z] == z2
        expected_score = (logpdf(normal, z1, 2., 1.)
            + logpdf(normal, z2, 6., 1.))
        @test isapprox(get_score(trace), expected_score)
        expected_weight = (logpdf(normal, z1, 2., 1.)
            - logpdf(normal, z1, 4., 1.))
        @test isapprox(weight, expected_weight)
        retval = get_retval(trace)
        @test length(retval) == 2
        @test retval[1] == z1
        @test retval[2] == z2
        @test retdiff == NoRetDiff()
        @test isnodiff(retdiff)
    end

    @testset "choice_gradients" begin
        z1, z2 = 1.1, 2.2
        xs = [1.0, 2.0]
        ys = [3.0, 4.0]

        function get_initial_trace()
            constraints = choicemap()
            constraints[1 => :z] = z1
            constraints[2 => :z] = z2
            (trace, _) = generate(bar, (xs, ys), constraints)
            trace
        end

        retval_grad = rand(2)

        expected_xs_grad = [logpdf_grad(normal, z1, 4., 1.)[2], logpdf_grad(normal, z2, 6., 1.)[2]]
        expected_ys_grad = [logpdf_grad(normal, z1, 4., 1.)[2], logpdf_grad(normal, z2, 6., 1.)[2]]
        expected_z2_grad = logpdf_grad(normal, z2, 6., 1.)[1] + retval_grad[2]

        # get gradients wrt xs and ys, and wrt address '2 => :z'
        trace = get_initial_trace()
        selection = select(2 => :z)
        (input_grads, choices, gradients) = choice_gradients(trace, selection, retval_grad)
        @test isapprox(input_grads[1], expected_xs_grad)
        @test isapprox(input_grads[2], expected_ys_grad)
        @test !has_value(choices, 1 => :z)
        @test choices[2 => :z] == z2
        @test !has_value(gradients, 1 => :z)
        @test isapprox(gradients[2 => :z], expected_z2_grad)
    end

    @testset "accumulate_param_gradients!" begin
        z1, z2 = 1.1, 2.2
        xs = [1.0, 2.0]
        ys = [3.0, 4.0]

        function get_initial_trace()
            constraints = choicemap()
            constraints[1 => :z] = z1
            constraints[2 => :z] = z2
            (trace, _) = generate(bar, (xs, ys), constraints)
            trace
        end

        retval_grad = rand(2)

        expected_xs_grad = [logpdf_grad(normal, z1, 4., 1.)[2], logpdf_grad(normal, z2, 6., 1.)[2]]
        expected_ys_grad = [logpdf_grad(normal, z1, 4., 1.)[2], logpdf_grad(normal, z2, 6., 1.)[2]]

        # get gradients wrt xs and ys
        trace = get_initial_trace()
        zero_param_grad!(foo, :std)
        input_grads = accumulate_param_gradients!(trace, retval_grad)
        @test isapprox(input_grads[1], expected_xs_grad)
        @test isapprox(input_grads[2], expected_ys_grad)
        expected_std_grad = (logpdf_grad(normal, z1, 4., 1.)[3]
            + logpdf_grad(normal, z2, 6., 1.)[3])
        @test isapprox(get_param_grad(foo, :std), expected_std_grad)
    end
end
