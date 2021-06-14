using Random; Random.seed!(1234)
using OrdinaryDiffEq
using Statistics
using ForwardDiff, Calculus
using DiffEqSensitivity
using Test


@testset "LSS" begin
  @testset "Lorentz single parameter" begin
    function lorenz!(du,u,p,t)
      du[1] = 10*(u[2]-u[1])
      du[2] = u[1]*(p[1]-u[3]) - u[2]
      du[3] = u[1]*u[2] - (8//3)*u[3]
    end

    p = [28.0]
    tspan_init = (0.0,30.0)
    tspan_attractor = (30.0,50.0)
    u0 = rand(3)
    prob_init = ODEProblem(lorenz!,u0,tspan_init,p)
    sol_init = solve(prob_init,Tsit5())
    prob_attractor = ODEProblem(lorenz!,sol_init[end],tspan_attractor,p)
    sol_attractor = solve(prob_attractor,Vern9(),abstol=1e-14,reltol=1e-14)

    g(u,p,t) = u[end]
    function dg(out,u,p,t,i)
      fill!(out, zero(eltype(u)))
      out[end] = one(eltype(u))
    end
    lss_problem1 = ForwardLSSProblem(sol_attractor, ForwardLSS(), g)
    lss_problem1a = ForwardLSSProblem(sol_attractor, ForwardLSS(), nothing, dg)
    lss_problem2 = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=DiffEqSensitivity.Cos2Windowing()), g)
    lss_problem2a = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=DiffEqSensitivity.Cos2Windowing()), nothing, dg)
    lss_problem3 = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=10), g)
    lss_problem3a = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=10), g, dg) #ForwardLSS with time dilation requires knowledge of g

    adjointlss_problem = AdjointLSSProblem(sol_attractor, AdjointLSS(alpha=10.0), g)
    adjointlss_problem_a = AdjointLSSProblem(sol_attractor, AdjointLSS(alpha=10.0), g, dg)

    res1 = DiffEqSensitivity.__solve(lss_problem1)
    res1a = DiffEqSensitivity.__solve(lss_problem1a)
    res2 = DiffEqSensitivity.__solve(lss_problem2)
    res2a = DiffEqSensitivity.__solve(lss_problem2a)
    res3 = DiffEqSensitivity.__solve(lss_problem3)
    res3a = DiffEqSensitivity.__solve(lss_problem3a)

    res4 = DiffEqSensitivity.__solve(adjointlss_problem)
    res4a = DiffEqSensitivity.__solve(adjointlss_problem_a)

    @test res1[1] ≈ 1 atol=5e-2
    @test res2[1] ≈ 1 atol=5e-2
    @test res3[1] ≈ 1 atol=5e-2

    @test res1 ≈ res1a atol=1e-10
    @test res2 ≈ res2a atol=1e-10
    @test res3 ≈ res3a atol=1e-10
    @test res3 ≈ res4 atol=1e-10
    @test res3 ≈ res4a atol=1e-10
  end

  @testset "Lorentz" begin
    function lorenz!(du,u,p,t)
      du[1] = p[1]*(u[2]-u[1])
      du[2] = u[1]*(p[2]-u[3]) - u[2]
      du[3] = u[1]*u[2] - p[3]*u[3]
    end

    p = [10.0, 28.0, 8/3]

    tspan_init = (0.0,30.0)
    tspan_attractor = (30.0,50.0)
    u0 = rand(3)
    prob_init = ODEProblem(lorenz!,u0,tspan_init,p)
    sol_init = solve(prob_init,Tsit5())
    prob_attractor = ODEProblem(lorenz!,sol_init[end],tspan_attractor,p)
    sol_attractor = solve(prob_attractor,Vern9(),abstol=1e-14,reltol=1e-14)

    g(u,p,t) = u[end] + sum(p)
    function dgu(out,u,p,t,i)
      fill!(out, zero(eltype(u)))
      out[end] = one(eltype(u))
    end
    function dgp(out,u,p,t,i)
      fill!(out, one(eltype(p)))
    end

    lss_problem = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=10), g)
    lss_problem_a = ForwardLSSProblem(sol_attractor, ForwardLSS(alpha=10), g, (dgu,dgp))
    adjointlss_problem = AdjointLSSProblem(sol_attractor, AdjointLSS(alpha=10.0), g)
    adjointlss_problem_a = AdjointLSSProblem(sol_attractor, AdjointLSS(alpha=10.0), g, (dgu,dgp))

    resfw = DiffEqSensitivity.__solve(lss_problem)
    resfw_a = DiffEqSensitivity.__solve(lss_problem_a)
    resadj = DiffEqSensitivity.__solve(adjointlss_problem)
    resadj_a = DiffEqSensitivity.__solve(adjointlss_problem_a)

    @test resfw ≈ resadj rtol=1e-10
    @test resfw ≈ resfw_a rtol=1e-10
    @test resfw ≈ resadj_a rtol=1e-10
  end
end
