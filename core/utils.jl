module Utils

using JuMP, CSV, DataFrames, YAML, Interpolations, Plots, Statistics

"""
Load time series data from a CSV file.
"""
function import_time_series(csv_file_path::String; delimiter::Char=',', decimal::Char='.')::DataFrame
    if !isfile(csv_file_path)
        error("The CSV file at path '$csv_file_path' does not exist.")
    end

    try
        data = CSV.read(csv_file_path, DataFrame; delim=delimiter, decimal=decimal)
        return data
    catch e
        error("Error loading CSV file: $(e.msg)")
    end
end

"""
Sample the generator efficiency curve at `n_samples` equally spaced relative output points,
excluding points where efficiency is zero to avoid invalid divisions later.
Also plots and saves the sampled efficiency curve into the results folder.
"""
function sample_efficiency_curve(gen_efficiency_df, n_samples)
    # Extract columns (make sure your CSV header matches exactly)
    relative_output = gen_efficiency_df[:, 1] ./ 100  # Normalize from 0–100% → 0–1
    efficiency = gen_efficiency_df[:, 2] ./ 100       # Normalize efficiency % → 0–1

    # Build interpolation
    interpolation = LinearInterpolation(relative_output, efficiency, extrapolation_bc=Line())

    # Sampling points (equally spaced between 0 and 1)
    sampled_relative_output = range(0, 1, length=n_samples)

    # Interpolated efficiencies at sampled points
    sampled_efficiency = [interpolation(r) for r in sampled_relative_output]

    # Remove sampled points where efficiency is zero
    valid_indices = findall(e -> e > 0, sampled_efficiency)
    sampled_relative_output = sampled_relative_output[valid_indices]
    sampled_efficiency = sampled_efficiency[valid_indices]

    # Plot and Save the Sampled Efficiency Curve
    plot(
        sampled_relative_output .* 100,     
        sampled_efficiency .* 100,           
        seriestype = :scatter,
        xlabel = "Relative Power Output (%)",
        ylabel = "Efficiency (%)",
        title = "Sampled Generator Efficiency Curve",
        legend = false,
        grid = true,
        markershape = :circle
    )

    # Save the plot
    savefig(joinpath(@__DIR__, "..", "results", "sampled_efficiency_curve.png"))
    println("Sampled efficiency curve saved to /results/sampled_efficiency_curve.png")

    return sampled_relative_output, sampled_efficiency
end

"""
Estimate effective battery calendar lifetime based on hourly ambient temperature profile.

Arguments:
- csv_path: path to the CSV file (8760 hourly temperature values)
- battery_chemistry: "Lithium_LFP", "Lithium_NMC", or "Lead_Acid"
- dod_level: typical depth of discharge (e.g., 0.8, 0.9)
- battery_degradation_path: path to yaml file with battery degradation data

Returns:
- calendar_lifetime_years: estimated effective calendar lifetime in years
"""
function estimate_calendar_lifetime(csv_path::String, battery_chemistry::String, dod_level::Float64, SOH_EOL::Float64, battery_degradation_path::String)

    # Load battery degradation data
    battery_degradation_data = YAML.load_file(battery_degradation_path)

    # Check if the battery chemistry is valid
    if !haskey(battery_degradation_data, battery_chemistry)
        error("Battery chemistry '$battery_chemistry' not found in degradation data.")
    end
    if !haskey(battery_degradation_data[battery_chemistry], "equations")
        error("Battery chemistry '$battery_chemistry' does not have equations defined.")
    end

    # Load the temperature time series
    df_temp = import_time_series(csv_path)
    temperatures = df_temp[!, 1]  # Assume first column has temperatures
    # Convert temperatures from Celsius to tenths of Celsius
    temperatures = temperatures ./ 10

    if battery_chemistry == "Lead_Acid"
        # Lead-Acid: fixed aging rate
        fixed_a = battery_degradation_data[battery_chemistry]["fixed"]["a"]
        calendar_aging_rate_hour = fill(fixed_a / 8760, 8760)
    else
        # Lithium chemistries: temperature-dependent polynomial
        coeffs_a = battery_degradation_data[battery_chemistry]["equations"][dod_level]["a"]

        # Polynomial evaluation: a0 + a1*T + a2*T^2 + a3*T^3
        calendar_aging_rate_year = (
            coeffs_a[1] .+ coeffs_a[2] .* temperatures .+ coeffs_a[3] .* temperatures.^2 .+ coeffs_a[4] .* temperatures.^3)

        # Convert [%/year] to [%/hour]
        calendar_aging_rate_hour = calendar_aging_rate_year ./ 8760
    end

    # Sum the hourly degradation over the year
    total_annual_fade = sum(calendar_aging_rate_hour)  # Total SOH loss per year

    # Effective Calendar Lifetime = Years until SOH reaches SOH_EOL
    # SOH loss needed = (1 - SOH_EOL)
    calendar_lifetime_years = (1.0 - SOH_EOL) / total_annual_fade

    return calendar_lifetime_years
end


function write_results_to_csv(model::Model, dispatch_path::String, load::Vector{Float64}, solar_unit_production::Vector{Float64}, has_generator::Bool)

    # Extract useful parameters
    parameters_path = joinpath(@__DIR__,"..", "inputs", "parameters.yaml")
    parameters = YAML.load_file(parameters_path)
    generator_nominal_capacity = parameters["generator"]["nominal_capacity"] 

    # Extract operation variables
    solar_units = value(model[:solar_units])
    solar_production = value.(model[:solar_production])
    battery_charge   = value.(model[:battery_charge])
    battery_discharge = value.(model[:battery_discharge])
    SOC             = value.(model[:SOC])
    lost_load       = value.(model[:lost_load])

    if has_generator
        generator_units = value(model[:generator_units])
        generator_production = value.(model[:generator_production])

        # If partial load is enabled, also extract fuel consumption
        if haskey(model, :generator_fuel)
            generator_fuel = value.(model[:generator_fuel])
        end
    end

    # Calculate solar maximum for each t to see how much was curtailed
    solar_max_production = solar_unit_production .* solar_units
    curtailment = solar_max_production .- solar_production

    # Create a DataFrame with the dispatch results
    energy_balance_table = DataFrame(
        "Time Step"               => 1:8760,
        "Load (kWh)"              => load,
        "Solar Production (kWh)"  => solar_production,
        "Curtailment (kWh)"       => curtailment,
        "Battery Charge (kWh)"    => battery_charge,
        "Battery Discharge (kWh)" => battery_discharge,
        "State of Charge (kWh)"   => SOC,
        "Lost Load (kWh)"         => lost_load
    )
    
    if has_generator
        energy_balance_table[!, "Generator Production (kWh)"] = generator_production

        if haskey(model, :generator_fuel)
            energy_balance_table[!, "Generator Fuel Consumption (liters)"] = generator_fuel

            # Add Instantaneous Generator Efficiency (kWh/liter)
            generator_efficiency = generator_production ./ generator_fuel
            energy_balance_table[!, "Generator Efficiency (kWh/liter)"] = generator_efficiency

            # Add Generator Load Factor (% of capacity)
            generator_capacity_kW = generator_units * generator_nominal_capacity
            generator_load_factor = generator_production ./ (generator_capacity_kW)  # [0-1]
            energy_balance_table[!, "Generator Load Factor (%)"] = generator_load_factor .* 100
        end
    end

    # Write the dispatch results to a CSV file
    CSV.write(dispatch_path, energy_balance_table)
    println("\nDispatch results written to $dispatch_path")
end


end