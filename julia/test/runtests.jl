using Bridgestan
using Test

@testset "bernoulli" begin
    # Bernoulli
    # CMDSTAN=/path/to/cmdstan/ make stan/bernoulli/bernoulli_model.so

    function bernoulli(y, p)
        sum(yn -> yn * log(p) + (1 - yn) * log(1 - p), y)
    end

    lib = joinpath(@__DIR__, "../../stan/bernoulli/bernoulli_model.so")
    data = joinpath(@__DIR__, "../../stan/bernoulli/bernoulli.data.json")

    model = Bridgestan.StanModel(lib, data)

    @test Bridgestan.name(model) == "bernoulli_model"

    y = [0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    R = 1000

    for _ in 1:R
        x = rand(Bridgestan.param_num(model))
        q = @. log(x / (1 - x)) # unconstrained scale
        (log_density, gradient) = Bridgestan.log_density_gradient(model, q, jacobian = 0)

        p = x[1]
        @test isapprox(log_density, bernoulli(y, p))

        constrained_parameters = Bridgestan.param_constrain(model, q)
        @test isapprox(constrained_parameters, x)

        unconstrained_parameters= Bridgestan.param_unconstrain(model, constrained_parameters)
        @test isapprox(unconstrained_parameters, q)
    end

    @test isapprox(Bridgestan.param_num(model), 1)
    @test isapprox(Bridgestan.param_unc_num(model), 1)
end


@testset "multi" begin
    # Multivariate Gaussian
    # CMDSTAN=/path/to/cmdstan/ make stan/multi/multi_model.so

    function gaussian(x)
        return -0.5 * x' * x
    end

    function grad_gaussian(x)
        return -x
    end

    lib = joinpath(@__DIR__, "../../stan/multi/multi_model.so")
    data = joinpath(@__DIR__, "../../stan/multi/multi.data.json")

    nt = Threads.nthreads()
    models = Tuple(Bridgestan.StanModel(lib, data) for _ in 1:nt)

    R = 1000
    ld = Vector{Bool}(undef, R)
    g = Vector{Bool}(undef, R)

    @sync for it in 1:nt
        Threads.@spawn for r in it:nt:R
            x = randn(Bridgestan.param_num(models[it]))
            (lp, grad) = Bridgestan.log_density_gradient(models[it], x)

            ld[r] = isapprox(lp, gaussian(x))
            g[r] = isapprox(grad, grad_gaussian(x))
        end
    end

    @test all(ld)
    @test all(g)
end


@testset "gaussian" begin
    # Guassian with positive constrained standard deviation
    # CMDSTAN=/path/to/cmdstan/ make stan/gaussian/gaussian_model.so

    lib = joinpath(@__DIR__, "../../stan/gaussian/gaussian_model.so")
    data = joinpath(@__DIR__, "../../stan/gaussian/gaussian.data.json")

    model = Bridgestan.StanModel(lib, data)

    theta = [0.2, 1.9]
    theta_unc = [0.2, log(1.9)]


    theta_test = Bridgestan.param_constrain(model, theta_unc)
    @test isapprox(theta, theta_test)

    theta_unc_test = Bridgestan.param_unconstrain(model, theta)
    @test isapprox(theta_unc, theta_unc_test)

    theta_json = "{\"mu\": 0.2, \"sigma\": 1.9}"
    theta_unc_j_test = Bridgestan.param_unconstrain_json(model, theta_json)
    @test isapprox(theta_unc, theta_unc_j_test)
end


@testset "fr_gaussian" begin
    # Full rank Gaussian
    # CMDSTAN=/path/to/cmdstan/ make stan/fr_gaussian/fr_gaussian_model.so

    function _covariance_constrain_transform(v, D)
        k = 0
        L = [j >= i ? (k += 1; v[k]) : 0 for i in 1:D, j in 1:D]'
        for d in 1:D
            L[d, d] = exp(L[d, d])
        end
        return L * L'
    end

    lib = joinpath(@__DIR__, "../../stan/fr_gaussian/fr_gaussian_model.so")
    data = joinpath(@__DIR__, "../../stan/fr_gaussian/fr_gaussian.data.json")

    model = Bridgestan.StanModel(lib, data)

    size = 16
    unc_size = 10

    @test isapprox(size, Bridgestan.param_num(model, include_tp=true, include_gq=true))
    @test isapprox(unc_size, Bridgestan.param_unc_num(model))

    D = 4
    a = randn(unc_size)
    b = Bridgestan.param_constrain(model, a)
    B = reshape(b, (D,D))
    B_expected = _covariance_constrain_transform(a, D)
    @test isapprox(B_expected, B)

    c = Bridgestan.param_unconstrain(model, b)
    @test isapprox(a, c)

    names = Bridgestan.param_names(model, include_tp=true, include_gq=true)
    name_eq = Vector{Bool}(undef, size)
    pos = 1
    for j = 1:4
        for i = 1:4
           name_eq[pos] = names[pos] == ("Omega." * string(i) * "." * string(j))
           pos = pos + 1
        end
    end
    @test all(name_eq)

    unc_names = Bridgestan.param_unc_names(model)
    name_unc_eq = Vector{Bool}(undef, unc_size)
    for n = 1:10
        name_unc_eq[n] = unc_names[n] == ("Omega." * string(n))
    end
    @test all(name_unc_eq)
end


@testset "simple" begin
    lib = joinpath(@__DIR__, "../../stan/simple/simple_model.so")
    data = joinpath(@__DIR__, "../../stan/simple/simple.data.json")

    model = Bridgestan.StanModel(lib, data)

    D = 5
    y = rand(D)
    lp, grad, hess = Bridgestan.log_density_hessian(model, y)

    @test isapprox(-y, grad)
    using LinearAlgebra
    @test isapprox(-Matrix(1.0I, D, D), hess)

end