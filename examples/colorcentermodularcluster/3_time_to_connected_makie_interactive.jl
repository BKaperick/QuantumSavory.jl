using Base.Threads
using WGLMakie
WGLMakie.activate!()
using JSServe
using Markdown

include("setup.jl");

"""Run a simulation until all links in the cluster state are established,
then report time to completion and average link fidelity."""
function run_until_connected(root_conf)
    net, sim, observables, conf = prep_sim(root_conf)
    # Run until all connections succeed
    while !all([net[v,:link_register] for v in edges(net)])
        SimJulia.step(sim)
    end
    # Calculate fidelity of each cluster vertex
    fid = map(vertices(net)) do v
        neighs = neighbors(net,v) # get the neighborhood of the vertex
        obs = observables[length(neighs)] # get the observable for the given neighborhood size
        regs = [net[i, 2] for i in [v, neighs...]]
        real(observable(regs, obs; time=now(sim))) # calculate the value of the observable
    end
    now(sim), mean(fid)
end

##
# Prepare functions that can repeatedly run simulations and store the results

const N = 100

function continue_results!(times,fids,current_step,conf_obs,running,max_time)
    timeout = 0
    recent_max_time = 0
    while running[] && timeout<10000
        time, fid = fetch(@spawn run_until_connected(conf_obs[])) # do not run heavy calculations on the main thread, even if async
        recent_max_time = max(0.99*recent_max_time, time)
        max_time[] = max_time[]*0.998 + recent_max_time*0.002
        times[][current_step[]] = time
        fids[][current_step[]] = fid
        current_step[] = current_step[]%N+1
        timeout+=1
        notify(times)
        notify(fids)
    end
    running[] = false
end

function fill_results!(times,fids,conf)
    for i in 1:length(times[])
        time, fid = run_until_connected(conf)
        times[][i] = time
        fids[][i] = fid
    end
end

def_times = Observable(zeros(Float64, N))
def_fids = Observable(zeros(Float64, N))

fill_results!(def_times,def_fids,root_conf)

##
# Prepare the Makie app for landing page

landing = App() do
    dom = md"""
    # Simulations of the generation of GHZ and 3×2 cluster states in Tin-vacancy color centers

    For simulations over many repetition of the state generation experiment consult the [Ensemble Sims Page](./ensemble).

    For single instances of the experiment with detailed visualizations consider the [Single Trajectory Sim Page](./single-trajectory). The parameter sliders in this simulation are not functional yet.

    ## A few notes on parameterization

    The success probability of a Barret-Kot procedure is

    P = η²/2

    where η is the efficiency of the heralding step. That efficiency itself is

    η = ηᵒᵖᵗ ξᴼᴮ F / (F-1 + (ξᴰᵂξᴱ)⁻¹ )

    where
    - ηᵒᵖᵗ is the efficiency of the optical routing
    - F is the Purcell factor
    - ξᴼᴮ is the optical branching coeff. of the emitter
    - ξᴰᵂ is the Debye-Waller coeff. of the emitter
    - ξᴱ is the quantum efficiency coeff. of the emitter

    ## The default parameter values

    The default parameter values for emitter properties are mostly taken from `10.1103/PhysRevLett.124.023602` and `10.1103/PhysRevX.11.041041`.
    For the nuclear spins we reused some NV⁻ data.

    ## A few things that are not modeled in detail

    But are easy to add when we get around to it...

    - time gating of the detectors might be quite important but it is not used
        - it would increase fidelity
        - it would decrease efficiency
    - mismatches between emitters (random or systematic) are lumped into "raw entanglement fidelity"
    - detector dark counts and other imperfections are lumped into "coincidence measurement fidelity"
    - most single-qubit gate times and fidelities are neglected
    - initialization of the nuclear and electronic spins is not modeled in detail
    - bleaching and charge state instability are not modeled
    - dead time from reconfiguring optical paths is not modeled
    - crosstalk in microwave control is not modeled
    - optical crosstalk and poor extinction are not modeled
    - decoupling the electronic and nuclear spin after a failed measurement is not modeled in detail
    """
    return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
end;

##
# Prepare the Makie app for the ensemble simulations

ensemble = App() do
    times = Observable(zeros(Float64, N))
    fids = Observable(zeros(Float64, N))
    times[] .= def_times[]
    fids[] .= def_fids[]
    max_time = Observable(maximum(def_times[]))
    current_step = Ref(1)
    conf = Observable(deepcopy(root_conf))

    # Plot the time to complete vs average fidelity

    F = Figure(resolution=(1200,600))
    F1 = F[1,1]
    ax = Axis(F1[2:5,1:4])
    ax_time = Axis(F1[1,1:4])
    ax_fid = Axis(F1[2:5,5])
    linkxaxes!(ax,ax_time)
    linkyaxes!(ax,ax_fid)
    ylims!(ax, 0-0.02, 1+0.02)
    scatter!(ax, times, fids, color=(:black, 0.2))
    hist!(ax_time, times, bins=15, normalization=:probability, color=:grey)
    hist!(ax_fid, fids, direction=:x, bins=15, normalization=:probability, color=:grey)
    ylims!(ax_time, 0, 0.2)
    xlims!(ax_time, 0, 1.2*max_time[])
    on(max_time) do t; xlims!(ax_time, 0, 1.2*t) end
    xlims!(ax_fid, 0, 0.2)
    hideydecorations!(ax_time)
    hidexdecorations!(ax_fid)
    ax.ylabel = "Fidelity of Completed Cluster"
    ax.xlabel = "Time to Prepare Complete Cluster (ms)"

    F[2, 1:2] = buttongrid = GridLayout(tellwidth = false)
    running = Observable(false)
    buttongrid[1,1] = b = Makie.Button(F, label = @lift($running ? "Stop" : "Run"))

    on(b.clicks) do _
        running[] = !running[]
    end
    on(running) do r
        r && @async continue_results!(times,fids,current_step,conf,running,max_time)
    end

    add_conf_sliders(F[1, 2], conf, root_conf)

    dom = md"""$(F.scene)
    # Simulations of the generation of 3×2 cluster states in Tin-vacancy color centers

    Each dot in the plot corresponds to one complete Monte Carlo simulation run.

    The overall fidelity of the generated cluster state is on the vertical axis.
    The time necessary for the completion of the experiment is on the horizontal axis.
    Histograms of these values are given in the side facets.

    To the right you can modify various hardware parameters live, while the simulation is running.
    Press "Run" to start the simulation. Only the last $(N) simulation results are shown.

    The plots zoom automatically to the regions of interest.
    Drag over the plot to select manual region to zoom in.
    `Ctrl`+click resets the view.

    Back at the [landing page](/..) you can view multiple other ways to simulate and visualize this cluster state preparation experiment.
    """
    return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
end;

##
# Prepare the Makie app for the single-trajectory visualization

function continue_singlerun!(sim, net,
    observables, conf,
    fids, fidsMax, fidsMin, ts,
    linkcolors,
    obs_rg,obs_1,obs_2,ax2,
    current_time, running)
    while running[]
        current_time[] += conf[].T2N/600
        fetch(@spawn run(sim, current_time[])) # do not run heavy calculations on the main thread, even if async

        fid = map(vertices(net)) do v
            neighs = neighbors(net,v)
            l = length(neighs)
            obs = observables[l]
            regs = [net[i, 2] for i in [v, neighs...]]
            real(observable(regs, obs, 0.0; time=now(sim)))
        end
        linkcolors[] .= fid
        push!(fids[],mean(fid))
        push!(fidsMax[],maximum(fid))
        push!(fidsMin[],minimum(fid))
        push!(ts[],now(sim))

        # update plots
        notify(ts)
        notify(linkcolors)
        notify(obs_rg)
        notify(obs_1)
        notify(obs_2)
        xlims!(ax2,max(0,ts[][end]-conf[].BK_mem_wait_time*5), nothing)
    end
end

singletraj = App() do
    net, sim, observables, conf = prep_sim(root_conf)
    conf = Observable(conf)
    current_time = Observable(0.0)

    F = Figure(resolution=(1900,800))

    # Plot of the quantum states in the registers
    subfig_rg, ax_rg, p_rg, obs_rg = registernetplot_axis(F[1:4,1],net; interactions=false)
    registercoords = p_rg[:registercoords]
    xlims!(ax_rg, -4,5) # TODO
    ylims!(ax_rg, -6,7) # TODO these two lims! calls should not be necessary

    # Plots of various metadata and locks
    _,_,_,obs_1 = resourceplot_axis(F[1:3,2],
        net,
        [:link_queue], [:espin_queue,:nspin_queue,:decay_queue];
        registercoords=registercoords,
        title="Processes and Queues")
    _,_,_,obs_2 = resourceplot_axis(F[4:6,2],
        net,
        [:link_register], [];
        registercoords=registercoords,
        title="Established Links")

    # A rather hackish and unstable way to add more information to the register plot
    # This plot will overlay with colored lines the fidelity of entanglement of each node
    linkcolors = Observable(fill(0.0,nv(net)))
    regcoords = p_rg[:registercoords]
    for (i,v) in enumerate(vertices(net))
        offset = Point2(0,1).+0.1*(i%7-4)
        ls = linesegments!(ax_rg, regcoords[][vcat([[v,n] for n in neighbors(net,v)]...)].+(offset),
            color=lift(x->fill(x[v],length(neighbors(net,v))),linkcolors),
            colormap = :Spectral,
            colorrange = (-1., 1.),
            linewidth=3,markerspace=:data)
        v==1 && Colorbar(subfig_rg[2,1],ls,vertical=false,flipaxis=false,label="Entanglement Stabilizer Expectation")
    end

    # Plot of the evolving mean fidelity with respect to time
    ts = Observable(Float64[0])
    fids = Observable(Float64[0])
    fidsMax = Observable(Float64[0])
    fidsMin = Observable(Float64[0])
    g = F[5:6,1]
    ax2 = Axis(g[1,1], xlabel="time (ms)", ylabel="Entanglement Stabilizer\nExpectation")
    la = stairs!(ax2,ts,fids,linewidth=5,label="Average")
    lb = stairs!(ax2,ts,fidsMax,color=:green,label="Best node")
    lw = stairs!(ax2,ts,fidsMin,color=:red,label="Worst node")
    Legend(g[1,2],[la,lb,lw],["Average","Best node","Worst node"],
        orientation = :vertical, tellwidth = true, tellheight = false)
    xlims!(0, nothing)
    ylims!(-0.05, 1.05)

    F[6, 3] = buttongrid = GridLayout(tellwidth = false)
    running = Observable(false)
    buttongrid[1,1] = b = Makie.Button(F, label = @lift($running ? "Stop" : "Run"))

    on(b.clicks) do _
        running[] = !running[]
    end
    on(running) do r
        r && @async continue_singlerun!(sim, net,
        observables, conf,
        fids, fidsMax, fidsMin, ts,
        linkcolors,
        obs_rg,obs_1,obs_2,ax2,
        current_time, running)
    end

    add_conf_sliders(F[1:5, 3], conf, root_conf)

    dom = md"""$(F.scene)
    # Simulations of the generation of 3×2 cluster states in Tin-vacancy color centers

    The top-left plot shows the state of the network of registers. Each register has two slots, one for an electron spin where the entanglement gets established through a Barrett-Kok protocol, and one for a nuclear spin for long term storage.
    The colored-line overlay on top of the registers gives the fidelity of the various operators stabilizing the cluster state.

    The plot at the bottom left gives the overall fidelity of the state, together with the fidelity of the best and worst components of the state, over time.

    To the right the various locks and resource queues being tracked by the simulation are plotted in real time. For instance, whether the electron spin is currently being reserved by an entangler process is shown in the top plot.

    To the right you can modify various hardware parameters before you run the simulation.
    Press "Run" to start the simulation.

    The parameter sliders in this simulation are not functional yet.

    Back at the [landing page](/..) you can view multiple other ways to simulate and visualize this cluster state preparation experiment.
    """
    return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
end;

##
# A helper to add parameter sliders to visualizations

function add_conf_sliders(fig,conf_obs,root_conf)
    sg = SliderGrid(
        fig,
        (label = "Raw Entanglement Fidelity", #BK_electron_entanglement_fidelity
            range = 0.85:0.005:1.0, format = "{:.2f}", startvalue = root_conf.BK_electron_entanglement_fidelity),
        #-> "BK_electron_entanglement_init_state",

        (label = "coincidence measurement fidelity", #BK_measurement_fidelity
            range = 0.85:0.005:1.0, format = "{:.2f}", startvalue = root_conf.BK_measurement_fidelity),

        (label = "optical circuit efficiency", #losses
            range = 0.01:0.01:1.0, format = "{:.2f}", startvalue = root_conf.losses),
        (label = "ξ optical branching",
            range = 0.5:0.01:1.0, format = "{:.2f}", startvalue = root_conf.ξ_optical_branching),
        (label = "ξ Debye-Waller",
            range = 0.5:0.01:1.0, format = "{:.2f}", startvalue = root_conf.ξ_debye_waller),
        (label = "ξ quantum efficiency",
            range = 0.5:0.01:1.0, format = "{:.2f}", startvalue = root_conf.ξ_quantum_efficiency),
        (label = "F Purcell",
            range = 1:100, format = "{:.2f}", startvalue = root_conf.F_purcell),
        #-> BK_total_efficiency -> BK_success_prob -> BK_success_distribution

        (label = "Barret-Kok attempt duration (ms)", #BK_electron_entanglement_gentime
            range = 0.001:0.001:0.1, format = "{:.3f}", startvalue = root_conf.BK_electron_entanglement_gentime),
        (label = "hyperfine coupling (kHz)", #hyperfine_coupling
            range = 5e3:1e3:80e3, format = "{:.2f}", startvalue = root_conf.hyperfine_coupling),

        (label = "T₁ᵉ (ms)", #T1E
            range = 0.1:0.1:20, format = "{:.2f}", startvalue = root_conf.T1E),
        (label = "T₂ᵉ (ms)", #T2E
            range = 0.001:0.001:0.08, format = "{:.3f}", startvalue = root_conf.T2E),
        (label = "T₂ⁿ (ms)", #T1E
            range = 100:100:2000, format = "{:.2f}", startvalue = root_conf.T2N),

        width = 600,
        tellheight = false)

    # TODO there should be a nicer way to link sliders to the configuration
    names = [:BK_electron_entanglement_fidelity, :BK_measurement_fidelity,
        :losses, :ξ_optical_branching, :ξ_debye_waller, :ξ_quantum_efficiency, :F_purcell,
        :BK_electron_entanglement_gentime, :hyperfine_coupling,
        :T1E, :T2E, :T2N]
    for (name,slider) in zip(names,sg.sliders)
        on(slider.value) do val
            conf_obs[] = (;conf_obs[]..., NamedTuple{(name,)}((val,))...)
        end
    end
end

##
# Serve the Makie app


isdefined(Main, :server) && close(server)
server = JSServe.Server(landing, "0.0.0.0", 8888);
JSServe.route!(server, "/" => landing);
JSServe.route!(server, "/ensemble" => ensemble);
JSServe.route!(server, "/single-trajectory" => singletraj);
wait(server.server_task[])
