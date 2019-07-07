using Flux, Flux.Data.MNIST, Statistics
using Flux: throttle, params
using Juno: @progress
#  using CuArrays

# Load data, binarise it, and partition into mini-batches of M.
X = (float.(hcat(vec.(MNIST.images())...)) .> 0.5) |> gpu
N, M = size(X, 2), 100
data = [X[:,i] for i in Iterators.partition(1:N,M)]


################################# Define Model #################################

# Latent dimensionality, # hidden units.
Dz, Dh = 5, 500

# Components of recognition model / "encoder" MLP.
A, μ, logσ = Dense(28^2, Dh, tanh) |> gpu, Dense(Dh, Dz) |> gpu, Dense(Dh, Dz) |> gpu
g(X) = (h = A(X); (μ(h), logσ(h)))
function sample_z(μ, logσ)
    eps = randn(Float32, size(μ)) |> gpu
    return μ + exp.(logσ) .* eps
end

# Generative model / "decoder" MLP.
f = Chain(Dense(Dz, Dh, tanh), Dense(Dh, 28^2, σ)) |> gpu


####################### Define ways of doing things with the model. #######################

# KL-divergence between approximation posterior and N(0, 1) prior.
kl_q_p(μ, logσ) = 0.5f0 * sum(exp.(2f0 .* logσ) + μ.^2 .- 1f0 .+ logσ.^2)

# logp(x|z) - conditional probability of data given latents.
function logp_x_z(x, z)
    p = f(z)
    ll = x .* log.(p .+ eps(Float32)) + (1f0 .- x) .* log.(1 .- p .+ eps(Float32))
    return sum(ll)
end

# Monte Carlo estimator of mean ELBO using M samples.
L̄(X) = ((μ̂, logσ̂) = g(X); (logp_x_z(X, sample_z(μ̂, logσ̂)) - kl_q_p(μ̂, logσ̂)) * 1 // M)

loss(X) = -L̄(X) + 0.01f0 * sum(x->sum(x.^2), params(f))

# Sample from the learned model.
modelsample() = rand.(Bernoulli.(f(z.(zeros(Dz), zeros(Dz)))))


################################# Learn Parameters ##############################

evalcb = throttle(() -> @show(-L̄(X[:, rand(1:N, M)])), 30)
opt = ADAM()
ps = params(A, μ, logσ, f)

@progress for i = 1:20
  @info "Epoch $i"
  Flux.train!(loss, ps, zip(data), opt, cb=evalcb)
end


################################# Sample Output ##############################

using Images

img(x) = Gray.(reshape(x, 28, 28))

cd(@__DIR__)
sample = hcat(img.([modelsample() for i = 1:10])...)
save("sample.png", sample)
