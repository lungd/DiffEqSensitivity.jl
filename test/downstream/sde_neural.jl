using DiffEqFlux, Flux, LinearAlgebra
using DiffEqNoiseProcess
using StochasticDiffEq
using Statistics
using DiffEqSensitivity
using DiffEqBase.EnsembleAnalysis

function sys!(du, u, p, t)
    r, e, μ, h, ph, z, i = p
    du[1] = e * 0.5 * (5μ - u[1]) # nutrient input time series
    du[2] = e * 0.05 * (10μ - u[2]) # grazer density time series
    du[3] = 0.2 * exp(u[1]) - 0.05 * u[3] - r * u[3] / (h + u[3]) * u[4] # nutrient concentration
    du[4] =
        r * u[3] / (h + u[3]) * u[4] - 0.1 * u[4] -
        0.02 * u[4]^z / (ph^z + u[4]^z) * exp(u[2] / 2.0) + i #Algae density
end

function noise!(du, u, p, t)
    du[1] = p[end] # n
    du[2] = p[end] # n
    du[3] = 0.0
    du[4] = 0.0
end

datasize = 10
tspan = (0.0f0, 3.0f0)
tsteps = range(tspan[1], tspan[2], length = datasize)
u0 = Float32[1.0, 1.0, 1.0, 1.0]

p_ = Float32[1.1, 1.0, 0.0, 2.0, 1.0, 1.0, 1e-6, 1.0]

prob = SDEProblem(sys!, noise!, u0, tspan, p_)
ensembleprob = EnsembleProblem(prob)

solution = solve(
    ensembleprob,
    SOSRI(),
    EnsembleThreads();  
    trajectories = 1000,
    abstol = 1e-5,
    reltol = 1e-5, 
    maxiters = 1e8, 
    saveat = tsteps,
)

(truemean, truevar) = Array.(timeseries_steps_meanvar(solution))

ann = FastChain(FastDense(4, 32, tanh), FastDense(32, 32, tanh), FastDense(32, 2))
α = initial_params(ann)

function dudt_(du, u, p, t)
    r, e, μ, h, ph, z, i = p_

    MM = ann(u, p)

    du[1] = e * 0.5 * (5μ - u[1]) # nutrient input time series
    du[2] = e * 0.05 * (10μ - u[2]) # grazer density time series
    du[3] = 0.2 * exp(u[1]) - 0.05 * u[3] - MM[1] # nutrient concentration
    du[4] = MM[2] - 0.1 * u[4] - 0.02 * u[4]^z / (ph^z + u[4]^z) * exp(u[2] / 2.0) + i #Algae density
    return nothing
end
function noise_(du, u, p, t)
    du[1] = p_[end]
    du[2] = p_[end]
    du[3] = 0.0
    du[4] = 0.0
    return nothing
end

prob_nn = SDEProblem(dudt_, noise_, u0, tspan, p = nothing)

function loss(θ)
    tmp_prob = remake(prob_nn, p = θ)
    ensembleprob = EnsembleProblem(tmp_prob)
    tmp_sol = Array(solve(
        ensembleprob,
        EM();
        dt = tsteps.step,
        trajectories = 100,
        sensealg = ReverseDiffAdjoint(),
       ))
    tmp_mean = mean(tmp_sol,dims=3)[:,:]
    tmp_var = var(tmp_sol,dims=3)[:,:]
    sum(abs2, truemean - tmp_mean) + 0.1 * sum(abs2, truevar - tmp_var), tmp_mean
end

const losses = []
callback(θ, l, pred) = begin
    push!(losses, l)
    if length(losses)%50 == 0
        println("Current loss after $(length(losses)) iterations: $(losses[end])")
    end
    false
end

res1 = DiffEqFlux.sciml_train(
    loss,
    α,
    ADAM(0.1),
    cb = callback,
    maxiters = 200,
)
