# Store both grid and density for KDE over the real line
immutable UnivariateKDE{R<:Range}
    x::R
    density::Vector{Float64}
end

# construct kernel from bandwidth
kernel_dist(::Type{Normal},w::Real) = Normal(0.0,w)
kernel_dist(::Type{Uniform},w::Real) = (s = w/std(Uniform(-1.0,1.0)); Uniform(s,s))

typealias LocationScale Union(Laplace,Logistic,TriangularDist)
kernel_dist{D}(::Type{D},w::Real) = (s = w/std(D(0.0,1.0)); D(0.0,s))


# Silverman's rule of thumb for KDE bandwidth selection
function kde_bandwidth(data::Vector{Float64}, alpha::Float64 = 0.9)
    # Determine length of data
    ndata = length(data)

    # Calculate width using variance and IQR
    var_width = std(data)
    q25, q75 = quantile(data, [0.25, 0.75])
    quantile_width = (q75 - q25) / 1.34

    # Deal with edge cases with 0 IQR or variance
    width = min(var_width, quantile_width)
    if width == 0.0
        if var_width == 0.0
            width = 1.0
        else
            width = var_width
        end
    end

    # Set bandwidth using Silverman's rule of thumb
    return alpha * width * ndata^(-0.2)
end


# Roughly based on:
#   B. W. Silverman (1982) "Algorithm AS 176: Kernel Density Estimation Using
#   the Fast Fourier Transform", Journal of the Royal Statistical
#   Society. Series C (Applied Statistics) , Vol. 31, No. 1, pp. 93-99
#   URL: http://www.jstor.org/stable/2347084
# and:
#   M. C. Jones and H. W. Lotwick (1984) "Remark AS R50: A Remark on Algorithm
#   AS 176. Kernal Density Estimation Using the Fast Fourier Transform",
#   Journal of the Royal Statistical Society. Series C (Applied Statistics) ,
#   Vol. 33, No. 1, pp. 120-122
#   URL: http://www.jstor.org/stable/2347674

# default kde range
# Should extend enough beyond the data range to avoid cyclic correlation from the FFT
function kde_range(data::RealVector, bandwidth::Real)
    lo, hi = extrema(data)
    lo - 4.0*bandwidth, hi + 4.0*bandwidth
end


# tabulate data for kde
function tabulate(data::RealVector, midpoints::Range)
    ndata = length(data)
    npoints = length(midpoints)
    s = step(midpoints)

    # Set up a grid for discretized data
    grid = zeros(Float64, npoints)
    ainc = 1.0 / (ndata*s*s)

    # weighted discetization (cf. Jones and Lotwick)
    for x in data
        k = searchsortedfirst(midpoints,x)
        j = k-1
        if 1 <= j <= npoints
            grid[j] += (midpoints[k]-x)*ainc
            grid[k] += (x-midpoints[j])*ainc
        end
    end

    # returns an un-convolved KDE    
    UnivariateKDE(midpoints, grid)
end



# convolve raw KDE with kernel
# TODO: use in-place fft
function conv(k::UnivariateKDE, dist::Distribution)
    # Transform to Fourier basis
    K = length(k.density)
    ft = rfft(k.density)

    # Convolve fft with characteristic function of kernel
    # empirical cf
    #  = \sum_{n=1}^N e^{i*t*X_n} / N
    #  = \sum_{k=0}^K e^{i*t*(a+k*s)} N_k / N
    #  = e^{i*t*a} \sum_{k=0}^K e^{-2pi*i*k*(-t*s*K/2pi)/K} N_k / N
    #  = A * fft(N_k/N)[-t*s*K/2pi + 1]
    c = -twoπ/(step(k.x)*K)
    for j = 1:length(ft)
        ft[j] *= cf(dist,(j-1)*c)
    end

    # Invert the Fourier transform to get the KDE
    UnivariateKDE(k.x, irfft(ft, K))
end


function kde(data::RealVector, midpoints::Range, dist::Distribution)
    k = tabulate(data, midpoints)
    conv(k,dist)
end

function kde(data::RealVector, dist::Distribution; 
             endpoints::(Real,Real)=kde_range(data,std(dist)), npoints::Int=2048)
    
    lo, hi = endpoints
    lo < hi || error("endpoints (a,b) must have a < b")

    step = (hi - lo) / npoints
    midpoints = lo:step:hi
    
    kde(data,midpoints,dist)
end

function kde(data::RealVector, midpoints::Range; 
            bandwidth=kde_bandwidth(data), kernel=Normal)
    bandwidth <= 0.0 && error("Bandwidth must be positive")
    dist = kernel_dist(kernel,bandwidth)
    kde(data,midpoints,dist)
end

function kde(data::RealVector; bandwidth=kde_bandwidth(data), kernel=Normal, 
             npoints::Int=2048, endpoints::(Real,Real)=kde_range(data,bandwidth))
    bandwidth <= 0.0 && error("Bandwidth must be positive")
    dist = kernel_dist(kernel,bandwidth)
    kde(data,dist;endpoints=endpoints,npoints=npoints)
end