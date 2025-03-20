# Importing the required packages and functions
using JuMP, GLPK
include(joinpath(@__DIR__, "utils.jl"))
using .Utils: import_time_series, write_results_to_csv


"""
Main function to run the regular sizing model.
"""
function main()

    # PRE-PROCESSING
    # --------------

    # Initialize parameters
    include(joinpath(@__DIR__, "parameters_initialization.jl"))

    # Define input paths relative to the current directory
    load_path = joinpath(@__DIR__,"..", "inputs", "load.csv")
    solar_production_path = joinpath(@__DIR__,"..", "inputs", "solar_production.csv")

    # Load time series data
    load = import_time_series(load_path)
    load = load[!, 1] # Extract the first column as a vector
    solar_unit_production = import_time_series(solar_production_path)
    solar_unit_production = solar_unit_production[!, 1] # Extract the first column as a vector

    # MODEL INITIALIZATION
    # --------------------

    # Initialize the optimization model
    println("\nInitializing the optimization model...")
    model = Model()
    
    # SETS 
    T = 8760 # Total number of time steps for operation time series [hours]

    # DECISION VARIABLES

    # System Sizing with unit committment if applicable
    if solar_integer_solution
        @variable(model, solar_units >= 0, integer=true, base_name="Solar_Capacity") # [kW]
    else
        @variable(model, solar_units >= 0, base_name="Solar_Capacity") # [kW]
    end
    if battery_integer_solution
        @variable(model, battery_units >= 0, integer=true, base_name="Battery_Capacity") # [kWh]
    else
        @variable(model, battery_units >= 0, base_name="Battery_Capacity") # [kWh]
    end
    if has_generator
        if generator_integer_solution
            @variable(model, generator_units >= 0, integer=true, base_name="Generator_Capacity") # [kW]
        else
            @variable(model, generator_units >= 0, base_name="Generator_Capacity") # [kW]
        end
    end

    # Operation
    @variable(model, solar_production[t=1:T] >= 0, base_name="Solar_Production") # [kWh]
    @variable(model, battery_charge[t=1:T] >= 0, base_name="Battery_Charge") # [kWh]
    @variable(model, battery_discharge[t=1:T] >= 0, base_name="Battery_Discharge") # [kWh]
    @variable(model, SOC[t=1:T], base_name="State_of_Charge") # [kWh]
    @variable(model, lost_load[t=1:T] >= 0, base_name="Lost_Load") # [kWh]
    if has_generator
        @variable(model, generator_production[t=1:T] >= 0, base_name="Generator_Production") # [kWh]
    end

    # CONSTRAINTS

    # Energy Balance
    if has_generator
        @constraint(model, [t=1:T], load[t] == solar_production[t] + (battery_discharge[t] - battery_charge[t]) + generator_production[t] + lost_load[t])
        # Generator Production
        @constraint(model, [t=1:T], generator_production[t] <= (generator_units*generator_nominal_capacity))
    else
        @constraint(model, [t=1:T], load[t] == solar_production[t] + (battery_discharge[t] - battery_charge[t]) + lost_load[t])
    end

    # Solar PV Operation
    @constraint(model, [t=1:T], solar_production[t] <= (solar_units*solar_unit_production[t]))
    
    # Battery Energy Flows
    @constraint(model, [t=1:T], battery_charge[t] <= ((battery_units*battery_nominal_capacity)/t_charge)*Δt)
    @constraint(model, [t=1:T], battery_discharge[t] <= ((battery_units*battery_nominal_capacity)/t_discharge)*Δt)

    # Battery SOC 
    @constraint(model, [t=1:T], SOC[t] >= SOC_min*(battery_units*battery_nominal_capacity))
    @constraint(model, [t=1:T], SOC[t] <= SOC_max*(battery_units*battery_nominal_capacity))
    @constraint(model, SOC[1] == (SOC_0*(battery_units*battery_nominal_capacity)) + (battery_charge[1]*η_charge - battery_discharge[1]*η_discharge)) # Initial SOC [kWh]
    @constraint(model, [t=2:T], SOC[t] == SOC[t-1] + (battery_charge[t]*η_charge - battery_discharge[t]*η_discharge)) # SOC continuity [kWh]
    @constraint(model, SOC[T] == SOC_0*(battery_units*battery_nominal_capacity))  # End-of-horizon SOC continuity [kWh]

    # Project costs
    if has_generator
        @expression(model, CAPEX, ((solar_units     * solar_nominal_capacity)     * solar_capex) + 
                                  ((battery_units   * battery_nominal_capacity)   * battery_capex) +
                                  ((generator_units * generator_nominal_capacity) * generator_capex))
    else
        @expression(model, CAPEX, ((solar_units     * solar_nominal_capacity)     * solar_capex) + 
                                  ((battery_units   * battery_nominal_capacity)   * battery_capex))  
    end

    # Discounted Replacement Cost
    if has_generator
        @expression(model, Replacement_Cost_npv, sum(((solar_units * solar_nominal_capacity * solar_capex) * discount_factor[y]) for y in solar_replacement_years) +
                                                 sum(((battery_units * battery_nominal_capacity * battery_capex) * discount_factor[y]) for y in battery_replacement_years) +
                                                 sum(((generator_units * generator_nominal_capacity * generator_capex) * discount_factor[y]) for y in generator_replacement_years))
    else
        @expression(model, Replacement_Cost_npv, sum(((solar_units * solar_nominal_capacity * solar_capex) * discount_factor[y]) for y in solar_replacement_years) +
                                                 sum(((battery_units * battery_nominal_capacity * battery_capex) * discount_factor[y]) for y in battery_replacement_years))
    end

    # Subsidies
    @expression(model, Subsidies, ((solar_units * solar_nominal_capacity) * solar_capex) * solar_subsidy_share)

    # Fixed yearly operation costs (as a share of annual CAPEX)
    if has_generator
        @expression(model, OPEX_fixed, ((solar_units     * solar_nominal_capacity)     * solar_capex) * solar_opex + 
                                       ((battery_units   * battery_nominal_capacity)   * battery_capex) * battery_opex +
                                       ((generator_units * generator_nominal_capacity) * generator_capex) * generator_opex)
    else
        @expression(model, OPEX_fixed, ((solar_units     * solar_nominal_capacity)     * solar_capex) * solar_opex + 
                                       ((battery_units   * battery_nominal_capacity)   * battery_capex) * battery_opex)
    end

    # Variable operational cost (depending on generation)
    if has_generator
        @expression(model, OPEX_variable[t=1:T], ((generator_production[t] / fuel_lhv) * fuel_cost))
    else
        @expression(model, OPEX_variable[t=1:T], 0)
    end
    
    # Total Discounted Operation costs
    @expression(model, OPEX_npv, sum((sum(OPEX_variable[t] for t in 1:T) + OPEX_fixed) * discount_factor[y] for y in 1:project_lifetime))

    # Salvage value
    if has_generator
        @expression(model, Salvage, ((solar_units     * solar_nominal_capacity)     * solar_capex)     * salvage_solar_fraction + 
                                    ((battery_units   * battery_nominal_capacity)   * battery_capex)   * salvage_battery_fraction + 
                                    ((generator_units * generator_nominal_capacity) * generator_capex) * salvage_generator_fraction)
    else
        @expression(model, Salvage, ((solar_units     * solar_nominal_capacity)     * solar_capex)     * salvage_solar_fraction + 
                                    ((battery_units   * battery_nominal_capacity)   * battery_capex)   * salvage_battery_fraction)
    end
    
    # Total Discounted Salvage value
    @expression(model, Salvage_npv, Salvage * discount_factor[project_lifetime])

    # Net Present Value
    @expression(model, NPC, (CAPEX - Subsidies) + Replacement_Cost_npv + OPEX_npv - Salvage_npv)

    # Optimization Constraints

    # Max Yearly Lost Load constraint
    @constraint(model, [t=1:T], (sum(lost_load[t] for t in 1:T)) <= max_lost_load_share * sum(load))

    # Max CAPEX constraint
    @constraint(model, CAPEX <= max_capex)

    # Minimum Renewable Penetration
    if has_generator
        @constraint(model, [t=1:T], (sum(solar_production[t] for t in 1:T)) >= min_res_share * ((sum((solar_production[t] + generator_production[t]) for t in 1:T))))
    end

    # OBJECTIVE FUNCTION 
    @objective(model, Min, NPC)

    println("Model initialized successfully")

    # SOLVING THE MODEL
    # -----------------

    # Initialize Ipopt solver
    optimizer = optimizer_with_attributes(GLPK.Optimizer)

    # Setting solver options
    solver_settings = parameters["solver_settings"]["glpk_options"]
    println("\nSolving the optimization model using GLPK...")
    for (key, value) in solver_settings
        set_optimizer_attribute(optimizer, key, value)
    end

    # Attach the solver to the model
    set_optimizer(model, optimizer)

    # Solve the optimization problem
    @time optimize!(model)
    solution_summary(model, verbose = true)

    # Display the main results
    println("\nSystem Sizing:")
    println("  Solar Capacity: ", value(solar_units)*solar_nominal_capacity, " kW")
    println("  Battery Capacity: ", value(battery_units)*battery_nominal_capacity, " kWh")
    if has_generator
        println("  Generator Capacity: ", value(generator_units)*generator_nominal_capacity, " kW")
    end
    println("\nProject Costs:")
    println("  Net Present Cost: ", round(value(NPC) / 1000, digits=2), " k$currency")
    println("  Total Investment Cost: ", round(value(CAPEX) / 1000, digits=2), " k$currency")
    println("  Total Subsidies: ", round(value(Subsidies) / 1000, digits=2), " k$currency")
    println("  Disc. Replacement Cost: ", round(value(Replacement_Cost_npv) / 1000, digits=2), " k$currency")
    println("  Disc. Total Operation Cost: ", round(value(OPEX_npv) / 1000, digits=2), " k$currency")
    println("  Disc. Salvage Value   : ", round(value(Salvage_npv) / 1000, digits=2), " k$currency")

    println("\nOptimal Operation:")
    println("  Total Annual Solar Production: ", round(sum(value(solar_production[t]) for t in 1:T) / 1000, digits=2), " MWh/year")
    println("  Total Annual Battery Discharge: ", round(sum(value(battery_discharge[t]) for t in 1:T) / 1000, digits=2), " MWh/year")
    println("  Total Annual Battery Charge: ", round(sum(value(battery_charge[t]) for t in 1:T) / 1000, digits=2), " MWh/year")
    if has_generator
        println("  Total Annual Generator Production: ", round(sum(value(generator_production[t]) for t in 1:T) / 1000, digits=2), " MWh/year")
    end
    println("  Lost Load Share: ", round(sum(value(lost_load[t]) for t in 1:T) / sum(load) * 100, digits=2), " % of total load")
    if has_generator
        println("  Renewable Penetration: ", round((sum(value(solar_production[t]) for t in 1:T) / sum((value(solar_production[t]) + value(generator_production[t])) for t in 1:T)) * 100, digits=2), " % of total generation")
    end

    # POST-PROCESSING
    # ---------------

    # File path for the results Excel file
    dispatch_path = joinpath(@__DIR__,"..", "results", "optimal_dispatch.csv")
    write_results_to_csv(model, dispatch_path, load, solar_unit_production, has_generator)

end

# Run the main function
main()



