module Utils

using JuMP, CSV, DataFrames, YAML

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

function write_results_to_csv(model::Model, dispatch_path::String, load::Vector{Float64}, solar_unit_production::Vector{Float64}, has_generator::Bool)

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
    end

    # Calculate solar maximum for each t to see how much was curtailed
    solar_max_production = solar_unit_production .* solar_units
    curtailment = solar_max_production .- solar_production

    # Create a DataFrame with the dispatch results
    energy_balance_table = DataFrame(
        "Time Step"           => 1:8760,
        "Load (kWh)"          => load,
        "Solar Production (kWh)"   => solar_production,
        "Curtailment (kWh)"   => curtailment,
        "Battery Charge (kWh)"    => battery_charge,
        "Battery Discharge (kWh)"   => battery_discharge,
        "State of Charge (kWh)"   => SOC,
        "Lost Load (kWh)"     => lost_load)
    
    if has_generator
        energy_balance_table[!, "Generator Production (kWh)"] = generator_production
    end

    # Write the dispatch results to a CSV file
    CSV.write(dispatch_path, energy_balance_table)
    println("Dispatch results written to $dispatch_path")

end

end