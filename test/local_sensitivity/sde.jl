using Test, LinearAlgebra
using OrdinaryDiffEq
using DiffEqSensitivity, StochasticDiffEq, DiffEqBase
using ForwardDiff, Calculus, ReverseDiff
using Random
using Plots

seed = 100
Random.seed!(seed)
abstol = 1e-4
reltol = 1e-4

u₀ = [0.5]
tstart = 0.0
tend = 1.0
dt = 0.05
trange = (tstart, tend)
t = tstart:dt:tend

f_oop_linear(u,p,t) = p[1]*u
σ_oop_linear(u,p,t) = p[2]*u

function g(u,p,t)
  sum(u.^2/2)
end

function dg!(out,u,p,t,i)
  (out.=-u)
end

p = [1.01,0.0]

# generate ODE adjoint results

prob_oop_ode = ODEProblem(f_oop_linear,u₀,(tstart,tend),p)
sol_oop_ode = solve(prob_oop_ode,Tsit5(),saveat=t,abstol=abstol,reltol=reltol)
res_ode_u0, res_ode_p = adjoint_sensitivities(sol_oop_ode,Tsit5(),dg!,t
	,abstol=abstol,reltol=reltol,sensealg=BacksolveAdjoint())

function G(p)
  tmp_prob = remake(prob_oop_ode,u0=eltype(p).(prob_oop_ode.u0),p=p,
                    tspan=eltype(p).(prob_oop_ode.tspan),abstol=abstol, reltol=reltol)
  sol = solve(tmp_prob,Tsit5(),saveat=t,abstol=abstol, reltol=reltol)
  #@show sol
  res = g(sol,p,nothing)
  @show res
  res
end
res_ode_forward = ForwardDiff.gradient(G,p)
#res_ode_reverse = ReverseDiff.gradient(G,p)
@test isapprox(res_ode_forward[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-4)
#@test isapprox(res_ode_reverse[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-4)
@test isapprox(res_ode_p'[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-4)


# SDE adjoint results (with noise == 0, so should agree with above)

Random.seed!(seed)
prob_oop_sde = SDEProblem(f_oop_linear,σ_oop_linear,u₀,trange,p)
sol_oop_sde = solve(prob_oop_sde,RKMil(interpretation=:Stratonovich),dt=1e-4,adaptive=false,save_noise=true)
res_sde_u0, res_sde_p = adjoint_sensitivities(sol_oop_sde,RKMil(interpretation=:Stratonovich),dg!,t
 	,abstol=abstol,reltol=reltol,sensealg=BacksolveAdjoint())

function GSDE(p)
  Random.seed!(seed)
  tmp_prob = remake(prob_oop_sde,u0=eltype(p).(prob_oop_sde.u0),p=p,
                    tspan=eltype(p).(prob_oop_sde.tspan)
					#,abstol=abstol, reltol=reltol
					)
  sol = solve(tmp_prob,RKMil(interpretation=:Stratonovich),dt=tend/10000,adaptive=false,saveat=t)
  A = convert(Array,sol)
  res = g(A,p,nothing)
  @show res
  res
end
res_sde_forward = ForwardDiff.gradient(GSDE,p)
res_sde_reverse = ReverseDiff.gradient(GSDE,p)
@test isapprox(res_sde_forward[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-2)
@test isapprox(res_sde_reverse[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-2)
@test isapprox(res_sde_p'[1], sum(@. u₀^2*exp(2*p[1]*t)*t), rtol = 1e-2)



# SDE adjoint results (with noise != 0)

p2 = [1.01,0.87]

Random.seed!(seed)
prob_oop_sde2 = SDEProblem(f_oop_linear,σ_oop_linear,u₀,trange,p2)
sol_oop_sde2 = solve(prob_oop_sde2,RKMil(interpretation=:Stratonovich),dt=1e-4,adaptive=false,save_noise=true)
res_sde_u02, res_sde_p2 = adjoint_sensitivities(sol_oop_sde2,RKMil(interpretation=:Stratonovich),dg!,t
 	,abstol=abstol,reltol=reltol,sensealg=BacksolveAdjoint())

function GSDE(p)
  Random.seed!(seed)
  tmp_prob = remake(prob_oop_sde2,u0=eltype(p2).(prob_oop_sde2.u0),p=p,
                    tspan=eltype(p).(prob_oop_sde2.tspan)
					#,abstol=abstol, reltol=reltol
					)
  sol = solve(tmp_prob,RKMil(interpretation=:Stratonovich),dt=tend/10000,adaptive=false,saveat=t)
  A = convert(Array,sol)
  res = g(A,p,nothing)
  @show res
  res
end
res_sde_forward2 = ForwardDiff.gradient(GSDE,p2)
res_sde_reverse2 = ReverseDiff.gradient(GSDE,p2)



tarray = collect(t)
noise = vec((@. sol_oop_sde2.W(tarray)))
Wfix = [W[1][1] for W in noise]
resp1 = sum(@. tarray*u₀^2*exp(2*(p2[1]-p2[2]^2/2)*tarray+2*p[2]*Wfix))
resp2 = sum(@. (p[2]*tarray+Wfix)*u₀^2*exp(2*(p2[1]-p2[2]^2/2)*tarray+2*p[2]*Wfix))

@test isapprox(res_sde_p2', res_sde_forward2, rtol = 1e-2)
#@test isapprox(res_sde_forward2[1], resp1, rtol = 1e-2)
#@test isapprox(res_sde_reverse2[1], resp1, rtol = 1e-2)
#@test isapprox(res_sde_p2'[1], resp1, rtol = 1e-2)
