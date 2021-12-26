const GeometricConicForm{T} = MOI.Utilities.GenericModel{
    T,
    MOI.Utilities.ObjectiveContainer{Float64},
    MOI.Utilities.VariablesContainer{Float64},
    MOI.Utilities.MatrixOfConstraints{
        Float64,
        MOI.Utilities.MutableSparseMatrixCSC{
            Float64,
            Int,
            # We use `OneBasedIndexing` as it is the same indexing as used
            # by `SparseMatrixCSC` so we can do an allocation-free conversion to
            # `SparseMatrixCSC`.
            MOI.Utilities.OneBasedIndexing,
        },
        Vector{Float64},
        ProductOfSets{Float64},
    },
}

mutable struct ConicDiff <: DiffModel
    # storage for problem data in matrix form
    model::GeometricConicForm{Float64}
    # includes maps from matrix indices to problem data held in `optimizer`
    # also includes KKT matrices
    # also includes the solution
    gradient_cache::Union{Nothing,ConicCache}

    # caches for sensitivity output
    # result from solving KKT/residualmap linear systems
    # this allows keeping the same `gradient_cache`
    # if only sensitivy input changes
    forw_grad_cache::Union{Nothing,ConicForwCache}
    back_grad_cache::Union{Nothing,ConicBackCache}

    # sensitivity input cache using MOI like sparse format
    input_cache::DiffInputCache

    x::Vector{Float64} # Primal
    s::Vector{Float64} # Slack
    y::Vector{Float64} # Dual
end
function ConicDiff()
    return ConicDiff(GeometricConicForm{Float64}(), nothing, nothing, nothing, DiffInputCache(), Float64[], Float64[], Float64[])
end

MOI.supports_incremental_interface(::ConicDiff) = true

function MOI.empty!(model::ConicDiff)
    MOI.empty!(model.model)
    model.gradient_cache = nothing
    model.forw_grad_cache = nothing
    model.back_grad_cache = nothing
    empty!(model.input_cache)
    empty!(model.x)
    empty!(model.s)
    empty!(model.y)
    return
end

MOI.is_valid(model::ConicDiff, idx::MOI.Index) = MOI.is_valid(model.model, idx)

function MOI.add_variables(model::ConicDiff, n)
    return MOI.add_variables(model.model, n)
end

function MOI.supports_constraint(model::ConicDiff, F::Type{MOI.VectorAffineFunction{Float64}}, ::Type{S}) where {S<:MOI.AbstractVectorSet}
    if add_set_types(model.model.constraints.sets, S)
        push!(model.model.constraints.caches, Tuple{F,S}[])
        push!(model.model.constraints.are_indices_mapped, BitSet())
    end
    return MOI.supports_constraint(model.model, F, S)
end

function MOI.supports_constraint(model::ConicDiff, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}
    return MOI.supports_constraint(model.model, F, S)
end

function MOI.Utilities.pass_nonvariable_constraints(
    dest::ConicDiff,
    src::MOI.ModelLike,
    idxmap::MOIU.IndexMap,
    constraint_types,
)
    MOI.Utilities.pass_nonvariable_constraints(dest.model, src, idxmap, constraint_types)
end

function MOI.Utilities.final_touch(model::ConicDiff, index_map)
    MOI.Utilities.final_touch(model.model, index_map)
end

function MOI.add_constraint(model::ConicDiff, func::MOI.AbstractFunction, set::MOI.AbstractSet)
    return MOI.add_constraint(model.model, func, set)
end

function MOI.copy_to(dest::ConicDiff, model::MOI.ModelLike)

    cone_types = unique!([S for (F, S) in MOI.get(model, MOI.ListOfConstraintTypesPresent())])
    set_set_types(dest.model.constraints.sets, cone_types)
    index_map = MOI.copy_to(dest.model, model)

    return index_map
end

function _enlarge_set(vec::Vector, idx, value)
    m = last(idx)
    if length(vec) < m
        n = length(vec)
        resize!(vec, m)
        fill!(view(vec, (n+1):m), NaN)
        vec[idx] = value
    end
    return
end

function MOI.set(model::ConicDiff, ::MOI.VariablePrimalStart, vi::MOI.VariableIndex, value)
    MOI.throw_if_not_valid(model, vi)
    _enlarge_set(model.x, vi.value, value)
end

function MOI.set(model::ConicDiff, ::MOI.ConstraintPrimalStart, ci::MOI.ConstraintIndex, value)
    MOI.throw_if_not_valid(model, ci)
    _enlarge_set(model.s, MOI.Utilities.rows(model.model.constraints, ci), value)
end

function MOI.set(model::ConicDiff, ::MOI.ConstraintDualStart, ci::MOI.ConstraintIndex, value)
    MOI.throw_if_not_valid(model, ci)
    _enlarge_set(model.y, MOI.Utilities.rows(model.model.constraints, ci), value)
end

function _gradient_cache(model::ConicDiff)
    if model.gradient_cache !== nothing
        return model.gradient_cache
    end

    # For theoretical background, refer Section 3 of Differentiating Through a Cone Program, https://arxiv.org/abs/1904.09043

    A = -convert(SparseMatrixCSC{Float64, Int}, model.model.constraints.coefficients)
    b = model.model.constraints.constants

    if MOI.get(model, MOI.ObjectiveSense()) == MOI.FEASIBILITY_SENSE
        c = spzeros(size(A, 2))
    else
        obj = MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
        c = sparse_array_representation(obj, size(A, 2)).terms
        if MOI.get(model, MOI.ObjectiveSense()) == MOI.MAX_SENSE
            c = -c
        end
    end

    # programs in tests were cross-checked against `diffcp`, which follows SCS format
    # hence, some arrays saved during `MOI.optimize!` are not same across all optimizers
    # specifically there's an extra preprocessing step for `PositiveSemidefiniteConeTriangle` constraint for SCS/Mosek

    # pre-compute quantities for the derivative
    m = A.m
    n = A.n
    N = m + n + 1
    # NOTE: w = 1.0 systematically since we asserted the primal-dual pair is optimal
    (u, v, w) = (model.x, model.y - model.s, 1.0)


    # find gradient of projections on dual of the cones
    Dπv = Dπ(v, model.model, model.model.constraints.sets)

    # Q = [
    #      0   A'   c;
    #     -A   0    b;
    #     -c' -b'   0;
    # ]
    # M = (Q- I) * B + I
    # with B =
    # [
    #  I    .   .    # Πx = x because x is a solution and hence satistfies the constraints
    #  .  Dπv   .
    #  .    .   1    # w >= 0, but in the solution x = 1
    # ]
    # see: https://stanford.edu/~boyd/papers/pdf/cone_prog_refine.pdf
    # for the definition of Π and why we get I and 1 for x and w respectectively
    # K is defined in (5), Π in sect 2, and projection sin sect 3

    M = [
        spzeros(n,n)     (A' * Dπv)    c
        -A               -Dπv + I      b
        -c'              -b' * Dπv     0.0
    ]
    # find projections on dual of the cones
    vp = π(v, model.model, model.model.constraints.sets)

    model.gradient_cache = ConicCache(
        M = M,
        vp = vp,
        Dπv = Dπv,
        A = A,
        b = b,
        c = c,
    )

    return model.gradient_cache
end

"""
    forward(model::ConicDiff)

Method to compute the product of the derivative (Jacobian) at the
conic program parameters `A`, `b`, `c`  to the perturbations `dA`, `db`, `dc`.
This is similar to [`forward`](@ref).

For theoretical background, refer Section 3 of Differentiating Through a Cone Program, https://arxiv.org/abs/1904.09043
"""
function forward(model::ConicDiff)
    gradient_cache = _gradient_cache(model)
    M = gradient_cache.M
    vp = gradient_cache.vp
    Dπv = gradient_cache.Dπv
    x = model.x
    y = model.y
    s = model.s
    A = gradient_cache.A
    b = gradient_cache.b
    c = gradient_cache.c

    objective_function = _convert(MOI.ScalarAffineFunction{Float64}, model.input_cache.objective)
    sparse_array_obj = sparse_array_representation(objective_function, length(c))
    dc = sparse_array_obj.terms

    db = zeros(length(b))
    _fill(S -> false, gradient_cache, model.input_cache, model.model.constraints.sets, db)
    (lines, cols) = size(A)
    nz = nnz(A)
    dAi = zeros(Int, 0)
    dAj = zeros(Int, 0)
    dAv = zeros(Float64, 0)
    sizehint!(dAi, nz)
    sizehint!(dAj, nz)
    sizehint!(dAv, nz)
    _fill(S -> false, gradient_cache, model.input_cache, model.model.constraints.sets, dAi, dAj, dAv)
    dA = sparse(dAi, dAj, dAv, lines, cols)

    m = size(A, 1)
    n = size(A, 2)
    N = m + n + 1
    # NOTE: w = 1 systematically since we asserted the primal-dual pair is optimal
    (u, v, w) = (x, y - s, 1.0)

    # g = dQ * Π(z/|w|) = dQ * [u, vp, 1.0]
    RHS = [dA' * vp + dc; -dA * u + db; -dc ⋅ u - db ⋅ vp]

    dz = if norm(RHS) <= 1e-400 # TODO: parametrize or remove
        RHS .= 0 # because M is square
    else
        lsqr(M, RHS)
    end

    du, dv, dw = dz[1:n], dz[n+1:n+m], dz[n+m+1]
    model.forw_grad_cache = ConicForwCache(du, dv, [dw])
    return nothing
    # dx = du - x * dw
    # dy = Dπv * dv - y * dw
    # ds = Dπv * dv - dv - s * dw
    # return -dx, -dy, -ds
end

"""
    backward(model::ConicDiff)

Method to compute the product of the transpose of the derivative (Jacobian) at the
conic program parameters `A`, `b`, `c`  to the perturbations `dx`, `dy`, `ds`.
This is similar to [`backward`](@ref).

For theoretical background, refer Section 3 of Differentiating Through a Cone Program, https://arxiv.org/abs/1904.09043
"""
function backward(model::ConicDiff)
    gradient_cache = _gradient_cache(model)
    M = gradient_cache.M
    vp = gradient_cache.vp
    Dπv = gradient_cache.Dπv
    x = model.x
    y = model.y
    s = model.s
    A = gradient_cache.A
    b = gradient_cache.b
    c = gradient_cache.c

    dx = zeros(length(c))
    for (vi, value) in model.input_cache.dx
        dx[vi.value] = value
    end
    dy = zeros(length(b))
    ds = zeros(length(b))

    m = size(A, 1)
    n = size(A, 2)
    N = m + n + 1
    # NOTE: w = 1 systematically since we asserted the primal-dual pair is optimal
    (u, v, w) = (x, y - s, 1.0)

    # dz = D \phi (z)^T (dx,dy,dz)
    dz = [
        dx
        Dπv' * (dy + ds) - ds
        - x' * dx - y' * dy - s' * ds
    ]

    g = if norm(dz) <= 1e-4 # TODO: parametrize or remove
        dz .= 0 # because M is square
    else
        lsqr(M, dz)
    end

    πz = [
        u
        vp
        1.0
    ]

    # TODO: very important
    # contrast with:
    # http://reports-archive.adm.cs.cmu.edu/anon/2019/CMU-CS-19-109.pdf
    # pg 97, cap 7.4.2

    model.back_grad_cache = ConicBackCache(g, πz)
    return nothing
    # dQ = - g * πz'
    # dA = - dQ[1:n, n+1:n+m]' + dQ[n+1:n+m, 1:n]
    # db = - dQ[n+1:n+m, end] + dQ[end, n+1:n+m]'
    # dc = - dQ[1:n, end] + dQ[end, 1:n]'
    # return dA, db, dc
end

function MOI.get(model::ConicDiff, ::ForwardOutVariablePrimal, vi::MOI.VariableIndex)
    i = vi.value
    du = model.forw_grad_cache.du
    dw = model.forw_grad_cache.dw
    return - (du[i] - model.x[i] * dw[])
end
function _get_db(model::ConicDiff, ci::CI{F,S}
) where {F<:MOI.AbstractVectorFunction,S}
    i = MOI.Utilities.rows(model.model.constraints, ci) # vector
    # i = ci.value
    n = length(model.x) # columns in A
    # db = - dQ[n+1:n+m, end] + dQ[end, n+1:n+m]'
    g = model.back_grad_cache.g
    πz = model.back_grad_cache.πz
    return lazy_combination(-, πz, g, length(g), n .+ i)
end
function _get_db(model::ConicDiff, ci::CI{F,S}
) where {F<:MOI.AbstractScalarFunction,S}
    i = ci.value
    n = length(model.x) # columns in A
    # db = - dQ[n+1:n+m, end] + dQ[end, n+1:n+m]'
    g = model.back_grad_cache.g
    πz = model.back_grad_cache.πz
    dQ_ni_end = - g[n+i] * πz[end]
    dQ_end_ni = - g[end] * πz[n+i]
    return - dQ_ni_end + dQ_end_ni
end
function _get_dA(model::ConicDiff, ci::CI{<:MOI.AbstractScalarFunction})
    j = vi.value
    i = ci.value
    n = length(model.x) # columns in A
    m = length(model.y) # lines in A
    # dA = - dQ[1:n, n+1:n+m]' + dQ[n+1:n+m, 1:n]
    g = model.back_grad_cache.g
    πz = model.back_grad_cache.πz
    return lazy_combination(-, g, πz, i, n .+ (1:n))
end
function _get_dA(model::ConicDiff, ci::CI{<:MOI.AbstractVectorFunction})
    i = MOI.Utilities.rows(model.model.constraints, ci) # vector
    # i = ci.value
    n = length(model.x) # columns in A
    m = length(model.y) # lines in A
    # dA = - dQ[1:n, n+1:n+m]' + dQ[n+1:n+m, 1:n]
    g = model.back_grad_cache.g
    πz = model.back_grad_cache.πz
    return lazy_combination(-, g, πz, i, n .+ (1:n))
end
