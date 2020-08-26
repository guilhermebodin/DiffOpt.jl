@testset "Testing forward on trivial QP" begin
    # using example on https://osqp.org/docs/examples/setup-and-solve.html
    Q = [4.0 1.0; 1.0 2.0]
    q = [1.0; 1.0]
    G = [1.0 1.0; 1.0 0.0; 0.0 1.0; -1.0 -1.0; -1.0 0.0; 0.0 -1.0]
    h = [1.0; 0.7; 0.7; -1.0; 0.0; 0.0];

    model = diff_optimizer(Ipopt.Optimizer)
    x = MOI.add_variables(model, 2)

    # define objective
    quad_terms = MOI.ScalarQuadraticTerm{Float64}[]
    for i in 1:2
        for j in i:2 # indexes (i,j), (j,i) will be mirrored. specify only one kind
            push!(
                quad_terms, 
                MOI.ScalarQuadraticTerm(Q[i,j],x[i],x[j])
            )
        end
    end

    objective_function = MOI.ScalarQuadraticFunction(
                            MOI.ScalarAffineTerm.(q, x),
                            quad_terms,
                            0.0
                        )
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), objective_function)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # add constraints
    for i in 1:6
        MOI.add_constraint(
            model,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(G[i,:], x), 0.0),
            MOI.LessThan(h[i])
        )
    end

    MOI.optimize!(model)
    
    @test model.primal_optimal ≈ [0.3; 0.7] atol=ATOL rtol=RTOL
end



@testset "Differentiating trivial QP 1" begin
    Q = [4.0 1.0; 1.0 2.0]
    q = [1.0; 1.0]
    G = [1.0 1.0;]
    h = [-1.0;]

    model = diff_optimizer(OSQP.Optimizer)
    x = MOI.add_variables(model, 2)

    # define objective
    quad_terms = MOI.ScalarQuadraticTerm{Float64}[]
    for i in 1:2
        for j in i:2 # indexes (i,j), (j,i) will be mirrored. specify only one kind
            push!(
                quad_terms, 
                MOI.ScalarQuadraticTerm(Q[i,j], x[i], x[j])
            )
        end
    end

    objective_function = MOI.ScalarQuadraticFunction(
                            MOI.ScalarAffineTerm.(q, x),
                            quad_terms,
                            0.0
                        )
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), objective_function)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # add constraint
    MOI.add_constraint(
        model,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(G[1, :], x), 0.0),
        MOI.LessThan(h[1])
    )

    MOI.optimize!(model)
    
    @test model.primal_optimal ≈ [-0.25; -0.75] atol=ATOL rtol=RTOL

    grad_wrt_h = backward!(model, ["h"], [1.0 1.0])[1]

    @test grad_wrt_h ≈ [1.0] atol=ATOL rtol=RTOL
end


# @testset "Differentiating a non-convex QP" begin
#     Q = [0.0 0.0; 1.0 2.0]
#     q = [1.0; 1.0]
#     G = [1.0 1.0;]
#     h = [-1.0;]

#     model = diff_optimizer(OSQP.Optimizer)
#     x = MOI.add_variables(model, 2)

#     # define objective
#     quad_terms = MOI.ScalarQuadraticTerm{Float64}[]
#     for i in 1:2
#         for j in i:2 # indexes (i,j), (j,i) will be mirrored. specify only one kind
#             push!(
#                 quad_terms, 
#                 MOI.ScalarQuadraticTerm(Q[i,j], x[i], x[j]),
#             )
#         end
#     end

#     objective_function = MOI.ScalarQuadraticFunction(
#                             MOI.ScalarAffineTerm.(q, x),
#                             quad_terms,
#                             0.0,
#                         )
#     MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), objective_function)
#     MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

#     # add constraint
#     MOI.add_constraint(
#         model,
#         MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(G[1, :], x), 0.0),
#         MOI.LessThan(h[1]),
#     )

#     @test_throws ErrorException MOI.optimize!(model) # should break
# end


@testset "Differentiating QP with inequality and equality constraints" begin
    # refered from: https://www.mathworks.com/help/optim/ug/quadprog.html#d120e113424
    # Find equivalent qpth program here - https://github.com/AKS1996/jump-gsoc-2020/blob/master/DiffOpt_tests_4_py.ipynb

    Q = [1.0 -1.0 1.0; 
        -1.0  2.0 -2.0;
        1.0 -2.0 4.0]
    q = [2.0; -3.0; 1.0]
    G = [0.0 0.0 1.0;
         0.0 1.0 0.0;
         1.0 0.0 0.0;
         0.0 0.0 -1.0;
         0.0 -1.0 0.0;
         -1.0 0.0 0.0;]
    h = [1.0; 1.0; 1.0; 0.0; 0.0; 0.0;]
    A = [1.0 1.0 1.0;]
    b = [0.5;]

    model = diff_optimizer(Ipopt.Optimizer)
    x = MOI.add_variables(model, 3)

    # define objective
    quad_terms = MOI.ScalarQuadraticTerm{Float64}[]
    for i in 1:3
        for j in i:3 # indexes (i,j), (j,i) will be mirrored. specify only one kind
            push!(
                quad_terms, 
                MOI.ScalarQuadraticTerm(Q[i,j], x[i], x[j])
            )
        end
    end

    objective_function = MOI.ScalarQuadraticFunction(
                            MOI.ScalarAffineTerm.(q, x),
                            quad_terms,
                            0.0
                        )
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), objective_function)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # add constraint
    for i in 1:6
        MOI.add_constraint(
            model,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(G[i, :], x), 0.0),
            MOI.LessThan(h[i])
        )
    end

    for i in 1:1
        MOI.add_constraint(
            model,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(A[i,:], x), 0.0),
            MOI.EqualTo(b[i])
        )
    end

    MOI.optimize!(model)

    z = model.primal_optimal
    
    @test z ≈ [0.0; 0.5; 0.0] atol=ATOL rtol=RTOL

    grads = backward!(model, ["Q","q","G","h","A","b"], [1.0 1.0 1.0])

    dl_dQ = grads[1]
    dl_dq = grads[2]
    dl_dG = grads[3]
    dl_dh = grads[4]
    dl_dA = grads[5]
    dl_db = grads[6]

    @test dl_dQ ≈ zeros(3,3)  atol=ATOL rtol=RTOL

    @test dl_dq ≈ zeros(3,1) atol=ATOL rtol=RTOL

    @test dl_dG ≈ zeros(6,3) atol=ATOL rtol=RTOL

    @test dl_dh ≈ zeros(6,1) atol=ATOL rtol=RTOL

    @test dl_dA ≈ [0.0 -0.5 0.0] atol=ATOL rtol=RTOL

    @test dl_db ≈ [1.0] atol=ATOL rtol=RTOL
end



# refered from https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contquadratic.jl#L3
# Find equivalent CVXPYLayers and QPTH code here:
#               https://github.com/AKS1996/jump-gsoc-2020/blob/master/DiffOpt_tests_1_py.ipynb
@testset "Differentiating MOI examples 1" begin
    # homogeneous quadratic objective
    # Min x^2 + xy + y^2 + yz + z^2
    # st  x + 2y + 3z >= 4 (c1)
    #     x +  y      >= 1 (c2)
    #     x, y, z \in R

    model = diff_optimizer(OSQP.Optimizer)
    v = MOI.add_variables(model, 3)
    @test MOI.get(model, MOI.NumberOfVariables()) == 3

    c1 = MOI.add_constraint(
        model,
        MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([-1.0, -2.0, -3.0], v),
            0.0),
        MOI.LessThan(-4.0)
    )
    c2 = MOI.add_constraint(
        model, 
        MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([-1.0, -1.0, 0.0], v),
            0.0),
        MOI.LessThan(-1.0)
    )

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    @test MOI.get(model, MOI.ObjectiveSense()) == MOI.MIN_SENSE

    obj = MOI.ScalarQuadraticFunction(
        MOI.ScalarAffineTerm{Float64}[], 
        MOI.ScalarQuadraticTerm.(
            [2.0, 1.0, 2.0, 1.0, 2.0],
            v[[1, 1, 2, 2, 3]],
            v[[1, 2, 2, 3, 3]]
        ),
        0.0
    )
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), obj)

    MOI.optimize!(model)

    z = model.primal_optimal

    @test z ≈ [4/7, 3/7, 6/7] atol=ATOL rtol=RTOL

    # obtain gradients
    grads = backward!(model, ["Q","q","G","h"], [1.0 1.0 1.0])

    dl_dQ = grads[1]
    dl_dq = grads[2]
    dl_dG = grads[3]
    dl_dh = grads[4]

    @test dl_dQ ≈ [-0.12244895  0.01530609 -0.11224488;
                    0.01530609  0.09183674  0.07653058;
                   -0.11224488  0.07653058 -0.06122449]  atol=ATOL rtol=RTOL

    @test dl_dq ≈ [-0.2142857;  0.21428567; -0.07142857] atol=ATOL rtol=RTOL

    @test dl_dG ≈ [0.05102035   0.30612245  0.255102;
                   0.06122443   0.36734694  0.3061224] atol=ATOL rtol=RTOL

    @test dl_dh ≈ [-0.35714284; -0.4285714] atol=ATOL rtol=RTOL
end



# refered from https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contquadratic.jl#L3
# Find equivalent CVXPYLayers and QPTH code here:
#               https://github.com/AKS1996/jump-gsoc-2020/blob/master/DiffOpt_tests_2_py.ipynb
@testset "Differentiating MOI examples 2 - non trivial backward pass vector" begin
    # non-homogeneous quadratic objective
    #    minimize 2 x^2 + y^2 + xy + x + y
    #       s.t.  x, y >= 0
    #             x + y = 1

    model = diff_optimizer(Ipopt.Optimizer)
    x = MOI.add_variable(model)
    y = MOI.add_variable(model)

    c1 = MOI.add_constraint(
        model,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], [x,y]), 0.0),
        MOI.EqualTo(1.0)
    )

    vc1 = MOI.add_constraint(
        model, 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0,0.0], [x,y]), 0.0), 
        MOI.LessThan(0.0)
    )
    @test vc1.value ≈ x.value atol=ATOL rtol=RTOL

    vc2 = MOI.add_constraint(
        model,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0,-1.0], [x,y]), 0.0), 
        MOI.LessThan(0.0)
    )
    @test vc2.value ≈ y.value atol=ATOL rtol=RTOL


    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    obj = MOI.ScalarQuadraticFunction(
        MOI.ScalarAffineTerm.([1.0, 1.0], [x, y]),
        MOI.ScalarQuadraticTerm.([4.0, 2.0, 1.0], [x, y, x], [x, y, y]),
        0.0
    )
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), obj)

    MOI.optimize!(model)

    z = model.primal_optimal
    ν = model.dual_optimal[1]   # can be accessed in the order constraints were added
    λ = model.dual_optimal[2:3]
    

    @test z ≈ [0.25, 0.75] atol=ATOL rtol=RTOL
    @test λ ≈ [0.0, 0.0]   atol=ATOL rtol=RTOL
    @test ν ≈ 11/4       atol=ATOL rtol=RTOL

    # obtain gradients
    dl_dz = [1.3 0.5]   # choosing a non trivial backward pass vector
    grads = backward!(model, ["Q", "q", "G", "h", "A", "b"], dl_dz)

    dl_dQ = grads[1]
    dl_dq = grads[2]
    dl_dG = grads[3]
    dl_dh = grads[4]
    dl_dA = grads[5]
    dl_db = grads[6]

    @test dl_dQ ≈ [-0.05   -0.05;
                   -0.05    0.15]  atol=ATOL rtol=RTOL

    @test dl_dq ≈ [-0.2; 0.2] atol=ATOL rtol=RTOL

    @test dl_dG ≈ [1e-8  1e-8; 1e-8 1e-8] atol=ATOL rtol=RTOL

    @test dl_dh ≈ [1e-8; 1e-8] atol=ATOL rtol=RTOL

    @test dl_dA ≈ [0.375 -1.075] atol=ATOL rtol=RTOL

    @test dl_db ≈ [0.7] atol=ATOL rtol=RTOL
end


@testset "Differentiating non trivial convex QP MOI" begin
    nz = 10
    nineq = 25
    neq = 10

    # read matrices from files
    names = ["P", "q", "G", "h", "A", "b"]
    matrices = []

    for name in names
        push!(matrices, readdlm(Base.Filesystem.abspath(Base.Filesystem.joinpath("data",name*".txt")), ' ', Float64, '\n'))
    end
        
    Q, q, G, h, A, b = matrices
    q = vec(q)
    h = vec(h)
    b = vec(b)

    optimizer = diff_optimizer(Ipopt.Optimizer)

    x = MOI.add_variables(optimizer, nz)

    # define objective
    quadratic_terms = MOI.ScalarQuadraticTerm{Float64}[]
    for i in 1:nz
        for j in i:nz # indexes (i,j), (j,i) will be mirrored. specify only one kind
            push!(quadratic_terms, MOI.ScalarQuadraticTerm(Q[i,j], x[i], x[j]))
        end
    end

    objective_function = MOI.ScalarQuadraticFunction(MOI.ScalarAffineTerm.(q, x), quadratic_terms, 0.0)
    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), objective_function)
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # set constraints
    for i in 1:nineq
        MOI.add_constraint(
            optimizer,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(G[i,:], x), 0.0),MOI.LessThan(h[i])
        )
    end

    for i in 1:neq
        MOI.add_constraint(
            optimizer,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(A[i,:], x), 0.0),MOI.EqualTo(b[i])
        )
    end

    MOI.optimize!(optimizer)

    # obtain gradients
    grads = backward!(optimizer, ["Q", "q", "G", "h", "A", "b"], ones(1,nz))  # using dl_dz=[1,1,1,1,1,....]

    # read gradients from files
    names = ["dP", "dq", "dG", "dh", "dA", "db"]
    grads_actual = []

    for name in names
        push!(grads_actual, readdlm(Base.Filesystem.abspath(Base.Filesystem.joinpath("data",name*".txt")), ' ', Float64, '\n'))
    end

    grads_actual[2] = vec(grads_actual[2])
    grads_actual[4] = vec(grads_actual[4])
    grads_actual[6] = vec(grads_actual[6])

    # testing differences
    for i in 1:size(grads)[1]
        @test grads[i] ≈  grads_actual[i] atol=1e-2 rtol=1e-2
    end
end


@testset "Differentiating LP; checking gradients for non-active contraints" begin
    # Issue #40 from Gurobi.jl
    # min  x
    # s.t. x >= 0
    #      x >= 3

    optimizer = diff_optimizer(Clp.Optimizer)

    x = MOI.add_variables(optimizer,1)

    # define objective
    objective_function = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0], x), 0.0)
    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objective_function)
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # set constraints
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0], x), 0.), 
        MOI.LessThan(0.0)
    )
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0], x), 0.), 
        MOI.LessThan(-3.0)
    )

    MOI.optimize!(optimizer)

    # obtain gradients
    grads = backward!(optimizer, ["G", "h"], ones(1,1))  # using dl_dz=[1,1,1,1,1,....]

    @test grads[1] ≈ [0.0; 3.0] atol=ATOL rtol=RTOL
    @test grads[2] ≈ [0.0; -1.0] atol=ATOL rtol=RTOL
end


@testset "Differentiating LP; checking gradients for non-active contraints" begin
    # refered from - https://en.wikipedia.org/wiki/Simplex_algorithm#Example

    # max 2x + 3y + 4z
    # s.t. 3x+2y+z <= 10
    #      2x+5y+3z <= 15
    #      x,y,z >= 0

    
    optimizer = diff_optimizer(SCS.Optimizer)
    v = MOI.add_variables(optimizer, 3)

    # define objective
    objective_function = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-2.0, -3.0, -4.0], v), 0.0)
    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objective_function)
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    # set constraints
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([3.0, 2.0, 1.0], v), 0.), 
        MOI.LessThan(10.0)
    )
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0, 5.0, 3.0], v), 0.), 
        MOI.LessThan(15.0)
    )
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0, 0.0, 0.0], v), 0.), 
        MOI.LessThan(0.0)
    )
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0, -1.0, 0.0], v), 0.), 
        MOI.LessThan(0.0)
    )
    MOI.add_constraint(
        optimizer,
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0, 0.0, -1.0], v), 0.), 
        MOI.LessThan(0.0)
    )

    MOI.optimize!(optimizer)

    # obtain gradients
    grads = backward!(optimizer, ["Q", "q", "G", "h"], ones(1,3))  # using dl_dz=[1,1,1,1,1,....]

    @test grads[1] ≈ zeros(3,3) atol=ATOL rtol=RTOL
    @test grads[2] ≈ zeros(3) atol=ATOL rtol=RTOL
    @test grads[3] ≈ [0.0 0.0 0.0;
                    0.0 0.0 -5/3;
                    0.0 0.0 5/3;
                    0.0 0.0 -10/3;
                    0.0 0.0 0.0]   atol=ATOL rtol=RTOL
    @test grads[4] ≈ [0.0; 1/3; -1/3; 2/3; 0.0]   atol=ATOL rtol=RTOL
end


@testset "Differentiating simple SOCP" begin
    # referred from https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contconic.jl#L789
    # find equivalent diffcp python program here: https://github.com/AKS1996/jump-gsoc-2020/blob/master/diffcp_socp_1_py.ipynb

    model = diff_optimizer(SCS.Optimizer)

    x,y,t = MOI.add_variables(model, 3)

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    ceq  = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(-1.0, t))], [1.0]), MOI.Zeros(1))
    cnon = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, y))], [-1/√2]), MOI.Nonnegatives(1))
    csoc = MOI.add_constraint(model, MOI.VectorAffineFunction(MOI.VectorAffineTerm.([1,2,3], MOI.ScalarAffineTerm.(1.0, [t,x,y])), zeros(3)), MOI.SecondOrderCone(3))

    MOI.optimize!(model)

    x = model.primal_optimal
    s = MOI.get(model, MOI.ConstraintPrimal(), model.con_idx)
    y = model.dual_optimal
    
    # these matrices are benchmarked with the output generated by diffcp
    # refer the python file mentioned above to get equivalent python source code
    @test x ≈ [-0.707107; 0.707107; 1.0] atol=ATOL rtol=RTOL
    @test s ≈ [[3.58469e-18], [2.62755e-17], [1.0, -0.707107, 0.707107]] atol=ATOL rtol=RTOL
    @test y ≈ [[1.41421], [1.0], [1.41421, 1.0, -1.0]] atol=ATOL rtol=RTOL

    dA = Matrix{Float64}(I, 5, 3)
    db = zeros(5)
    dc = zeros(3)
    
    dx, dy, ds = backward_conic!(model, dA, db, dc)

    @test dx ≈ [1.12132144; 0.707107; 0.70710656] atol=ATOL rtol=RTOL
    @test ds ≈ [0.0; 0.0; -2.92893438e-01;  1.12132144e+00; 7.07106999e-01]  atol=ATOL rtol=RTOL
    @test dy ≈ [2.4142175;   5.00000557;  3.8284315;   1.414214;   -4.00000495] atol=ATOL rtol=RTOL
end

@testset "Differentiating simple PSD program" begin
    # refered from https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contconic.jl#L2339
    # find equivalent diffcp program here: https://github.com/AKS1996/jump-gsoc-2020/blob/master/diffcp_sdp_1_py.ipynb
    
    model = diff_optimizer(SCS.Optimizer)

    X = MOI.add_variables(model, 3)
    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction{Float64}(vov), 
        MOI.PositiveSemidefiniteConeTriangle(2)
    )

    c  = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction(
            [MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, X[2]))],
            [-1.0]
        ), 
        MOI.Zeros(1)
    )
    
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [X[1], X[end]]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    
    sol = MOI.optimize!(model)

    x = sol.primal
    s = sol.slack
    y = sol.dual

    @test x ≈ ones(3) atol=ATOL rtol=RTOL
    @test s ≈ [0.0; 1.0; 1.41421; 1.0] atol=ATOL rtol=RTOL
    @test y ≈ [1.99999496;  1.0; -1.41421356;  1.]  atol=ATOL rtol=RTOL

    dA = ones(4, 3)
    db = ones(4)
    dc = ones(3)
        
    dx, dy, ds = backward_conic!(model, dA, db, dc)

    @test dx ≈ [2.58577489; 1.99999496; 2.58577489] atol=ATOL rtol=RTOL
    @test ds ≈ [0.0; 5.85779924e-01; 8.28417913e-01; 5.85779924e-01] atol=ATOL rtol=RTOL
    @test dy ≈ [10.75732613;  3.5857814;  -5.07106069;  3.5857814 ] atol=ATOL rtol=RTOL
end


@testset "Differentiating conic with PSD and SOC constraints" begin
    # refer https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contconic.jl#L2417
    # find equivalent diffcp example here - https://github.com/AKS1996/jump-gsoc-2020/blob/master/diffcp_sdp_2_py.ipynb

    model = diff_optimizer(SCS.Optimizer)

    δ = √(1 + (3*√2+2)*√(-116*√2+166) / 14) / 2
    ε = √((1 - 2*(√2-1)*δ^2) / (2-√2))
    y2 = 1 - ε*δ
    y1 = 1 - √2*y2
    obj = y1 + y2/2
    k = -2*δ/ε
    x2 = ((3-2obj)*(2+k^2)-4) / (4*(2+k^2)-4*√2)
    α = √(3-2obj-4x2)/2
    β = k*α

    X = MOI.add_variables(model, 6)
    x = MOI.add_variables(model, 3)

    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(model, MOI.VectorAffineFunction{Float64}(vov), MOI.PositiveSemidefiniteConeTriangle(3))
    cx = MOI.add_constraint(model, MOI.VectorAffineFunction{Float64}(MOI.VectorOfVariables(x)), MOI.SecondOrderCone(3))

    c1 = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction(
            MOI.VectorAffineTerm.(1:1, MOI.ScalarAffineTerm.([1., 1., 1., 1.], [X[1], X[3], X[end], x[1]])), 
            [-1.0]
        ), 
        MOI.Zeros(1)
    )
    c2 = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction(
            MOI.VectorAffineTerm.(1:1, MOI.ScalarAffineTerm.([1., 2, 1, 2, 2, 1, 1, 1], [X; x[2]; x[3]])), 
            [-0.5]
        ), 
        MOI.Zeros(1)
    )

    objXidx = [1:3; 5:6]
    objXcoefs = 2*ones(5)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
    MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([objXcoefs; 1.0], [X[objXidx]; x[1]]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    sol = MOI.optimize!(model)

    x = sol.primal
    s = sol.slack
    y = sol.dual

    @test x ≈ [ 0.21725121; -0.25996907;  0.31108582;  0.21725009; -0.25996907;  0.21725121;
                0.2544097;   0.17989425;  0.17989425] atol=ATOL rtol=RTOL
    @test s ≈ [ 3.62815765e-18;  9.13225075e-18;  2.54409397e-01;  1.79894610e-01;
                1.79894610e-01;  2.17250333e-01; -3.67650666e-01;  3.07238368e-01;
                3.11085856e-01; -3.67650666e-01;  2.17250333e-01] atol=ATOL rtol=RTOL
    @test y ≈ [ 0.54475556;  0.32190866;  0.45524724; -0.32190841; -0.32190841;  1.13333458;
                0.95896711; -0.45524826;  1.13333631;  0.95896711;  1.13333458]  atol=ATOL rtol=RTOL

    dA = ones(11, 9)
    db = ones(11)
    dc = ones(9)
        
    dx, dy, ds = backward_conic!(model, dA, db, dc)

    @test dx ≈ [ 1.61704223; -0.5569146;  -0.7471691;   1.60033013; -0.5569146;
             1.61704223; -2.42981306; -1.7014106;  -1.7014106 ]  atol=ATOL rtol=RTOL
    @test ds ≈ [0.0; 0.0; -2.48690962e+00; -1.75851065e+00;  -1.75851065e+00;
                1.55994869e+00; -8.44690838e-01;  2.20610060e+00; -8.04264939e-01;
                -8.44690838e-01;  1.55994869e+00]  atol=ATOL rtol=RTOL
    @test dy ≈ [ 2.05946425;  9.70955435;  4.48131535; -3.16876847; -3.16876847;
                -5.22822899; -9.10636942; -9.10637304; -5.22823314; -9.10636942; -5.22822899]  atol=ATOL rtol=RTOL
end

@testset "Differentiating conic with PSD and POS constraints" begin
    # refer https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contconic.jl#L2575
    # find equivalent diffcp program here - https://github.com/AKS1996/jump-gsoc-2020/blob/master/diffcp_sdp_3_py.ipynb

    model = diff_optimizer(SCS.Optimizer)

    x = MOI.add_variables(model, 7)
    @test MOI.get(model, MOI.NumberOfVariables()) == 7

    η = 10.0

    c1  = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction(
            MOI.VectorAffineTerm.(1, MOI.ScalarAffineTerm.(-1.0, x[1:6])),
            [η]
        ), 
        MOI.Nonnegatives(1)
    )
    c2 = MOI.add_constraint(model, MOI.VectorAffineFunction(MOI.VectorAffineTerm.(1:6, MOI.ScalarAffineTerm.(1.0, x[1:6])), zeros(6)), MOI.Nonnegatives(6))
    α = 0.8
    δ = 0.9
    c3 = MOI.add_constraint(model, MOI.VectorAffineFunction(MOI.VectorAffineTerm.([fill(1, 7); fill(2, 5);     fill(3, 6)],
                                                            MOI.ScalarAffineTerm.(
                                                            [ δ/2,       α,   δ, δ/4, δ/8,      0.0, -1.0,
                                                                -δ/(2*√2), -δ/4, 0,     -δ/(8*√2), 0.0,
                                                                δ/2,     δ-α,   0,      δ/8,      δ/4, -1.0],
                                                            [x[1:7];     x[1:3]; x[5:6]; x[1:3]; x[5:7]])),
                                                            zeros(3)), MOI.PositiveSemidefiniteConeTriangle(2))
    c4 = MOI.add_constraint(
        model, 
        MOI.VectorAffineFunction(
            MOI.VectorAffineTerm.(1, MOI.ScalarAffineTerm.(0.0, [x[1:3]; x[5:6]])),
            [0.0]
        ), 
        MOI.Zeros(1)
    )

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x[7])], 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    sol = MOI.optimize!(model)

    x = sol.primal
    s = sol.slack
    y = sol.dual

    @test x' ≈ [6.66666667e+00 -3.88359992e-11  3.33333333e+00 -6.85488543e-12  6.02940183e-11 -6.21696364e-11  1.90192379e+00] atol=ATOL rtol=RTOL
    @test s' ≈ [0.00000000e+00  4.29630707e-17  6.66666667e+00  0.0   3.33333333e+00  6.63144880e-17  3.31758339e-17  0.0  4.09807621e+00 -3.00000000e+00  1.09807621e+00] atol=ATOL rtol=RTOL
    @test y' ≈ [0. 0.19019238 0. 0.12597667 0. 0.14264428 0.14264428 0.01274047 0.21132487 0.57735027 0.78867513]  atol=ATOL rtol=RTOL

    dA = ones(11, 7)
    db = ones(11)
    dc = ones(7)

    dx, dy, ds = backward_conic!(model, dA, db, dc)

    @test dx' ≈ [-42.240497    10.90192379 -12.26912194  10.90192379  10.90192379  10.90192379 -23.89209324] atol=ATOL rtol=RTOL
    @test ds' ≈ [-0.00000000e+00 0.0 -5.31424208e+01 0.0 -2.31710457e+01 0.0 0.0 0.0 -4.65932563e+00  3.41086309e+00 -1.24846254e+00] atol=ATOL rtol=RTOL
    @test dy' ≈ [-0. -3.79855654 -0.         -0.40206065 -0.         -0.45525613 -0.45525613 -0.04066184 -0.67445353 -1.84264131 -2.51709484] atol=ATOL rtol=RTOL
end


@testset "Differentiating a simple PSD" begin
    # refer https://github.com/jump-dev/MathOptInterface.jl/blob/master/src/Test/contconic.jl#L2643
    # find equivalent diffcp program here - https://github.com/AKS1996/jump-gsoc-2020/blob/master/diffcp_sdp_0_py.ipynb

    model = DiffOpt.diff_optimizer(SCS.Optimizer)

    x = MOI.add_variable(model)
    fx = MOI.SingleVariable(x)

    func = MOIU.operate(vcat, Float64, fx, one(Float64), fx, one(Float64), one(Float64), fx)

    c = MOI.add_constraint(model, func, MOI.PositiveSemidefiniteConeTriangle(3))

    MOI.set(model, MOI.ObjectiveFunction{MOI.SingleVariable}(), MOI.SingleVariable(x))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    sol = MOI.optimize!(model)

    x = sol.primal
    s = sol.slack
    y = sol.dual

    @test x' ≈ [1.0] atol=ATOL rtol=RTOL
    @test s' ≈ [1.         1.41421356 1.41421356 1.         1.41421356 1.        ] atol=ATOL rtol=RTOL
    @test y' ≈ [ 0.33333333 -0.23570226 -0.23570226  0.33333333 -0.23570226  0.33333333]  atol=ATOL rtol=RTOL

    dA = ones(6, 1)
    db = ones(6)
    dc = ones(1)

    dx, dy, ds = DiffOpt.backward_conic!(model, dA, db, dc)

    @test dx' ≈ zeros(1) atol=ATOL rtol=RTOL
    @test ds  ≈ zeros(6) atol=ATOL rtol=RTOL
    @test dy' ≈ [ 0.43096441 -0.30473785 -0.30473785  0.43096441 -0.30473785  0.43096441] atol=ATOL rtol=RTOL
end