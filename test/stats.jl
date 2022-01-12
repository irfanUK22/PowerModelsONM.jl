@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "settings" => "../test/data/settings.json",
        "inverters" => "../test/data/inverters.json",
        "output" => "test_output.json",
        "pretty-print" => true,
        "faults" => "../test/data/faults.json",
        "skip" => ["stability"],  # TODO bug in upstream PowerModelsStability: if an object in inverters is DISABLED, error in calc_connected_components
        "opt-switch-algorithm" => "global",
        "opt-switch-solver" => "mip_solver",
        "opt-disp-formulation" => "lindistflow",
        "fix-small-numbers" => true,
        "quiet" => true
    )

    args = entrypoint(deepcopy(orig_args))

    @testset "test output schema" begin
        @test validate_output(args["output_data"])
    end

    @testset "test action stats" begin
        @test args["output_data"]["Device action timeline"] == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]

        @test args["output_data"]["Switch changes"] == [String[], ["671700"], ["671692"], ["703800"], ["701702"], ["800801"], String[], ["801675", "671692"]]

        @test all(isapprox.(metadata["mip_gap"], 0.0; atol=1e-4) for metadata in args["output_data"]["Optimal switching metadata"])
    end

    @testset "test dispatch stats" begin
        @test length(args["output_data"]["Powerflow output"]) == 8
        @test all(all(haskey(ts, k) for k in ["voltage_source", "generator", "solar", "storage", "bus", "switch"]) for ts in args["output_data"]["Powerflow output"])

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], [763.0, 781.0, 796.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], [446.0, 418.0, 447.0]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["real power setpoint (kW)"], [2.33, 2.33, 2.33]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["reactive power setpoint (kVar)"], [-2.35, -2.35, -2.35]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"], [0.0, 0.0, 0.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"], [0.0, 0.0, 0.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], args["output_data"]["Powerflow output"][7]["bus"]["800"]["voltage (V)"]; atol=1e-4))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["702"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end

    @testset "test fault stats" begin
        @test all(isempty(args["output_data"]["Fault studies metadata"][i]) for i in 1:3)
        @test all(!isempty(args["output_data"]["Fault studies metadata"][i]) for i in 4:8)
    end

    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [36.4, 33.0, 23.0, 9.72, 51.7, 63.5, 82.2, 101.0]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [0.0, 0.0, 7.34, 6.52, 8.39, 3.43, 0.187, 6.91]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [95.4, 95.4, 88.0, 88.8, 87.0, 91.9, 95.2, 88.5]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [14.3, 18.0, 74.1, 92.6, 74.1, 93.9, 92.6, 92.8]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], [0.0, 0.0, 238.0, 240.0, 240.0, 241.0, 241.0, 452.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [75.1, 43.1, 125.0, 166.0, -33.8, -147.0, -233.0, -223.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [0.0, 0.0, 6.99, 203.0, 96.9, 36.6, 0.0, 0.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [2340.0, 2400.0, 2520.0, 3040.0, 3140.0, 3500.0, 3380.0, 2930.0]; atol=1e1))
    end

    @testset "test stability stats" begin
        @test isempty(args["output_data"]["Small signal stable"])
    end

    @testset "test missing events arg" begin
        _args = deepcopy(orig_args)
        delete!(_args, "events")
        _args["skip"] = ["switching", "dispatch", "stability", "faults"]

        _args = entrypoint(_args)

        @test isa(_args["events"], Dict{String,Any}) && isempty(_args["events"])
    end
end
