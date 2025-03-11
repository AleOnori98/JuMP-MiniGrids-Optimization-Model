using YAML

# Construct the path to the YAML file dynamically relative to this script's location
parameters_path = joinpath(@__DIR__,"..", "inputs", "parameters.yaml")

# Load project settings and parameters
parameters = YAML.load_file(parameters_path)

# Extract project settings
project_lifetime = parameters["project_settings"]["project_lifetime"] 
discount_rate = parameters["project_settings"]["discount_rate"] 
currency = parameters["project_settings"]["currency"] 

# Extract optimization settings
max_lost_load_share = parameters["optimization_settings"]["max_lost_load_share"]
max_capex = parameters["optimization_settings"]["max_capex"]
min_res_share = parameters["optimization_settings"]["min_res_share"]
solar_integer_solution = parameters["optimization_settings"]["solar_integer_solution"]
battery_integer_solution = parameters["optimization_settings"]["battery_integer_solution"]
if has_generator
    generator_integer_solution = parameters["optimization_settings"]["generator_integer_solution"]
end

# Extract Solar PV params
solar_nominal_capacity = parameters["solar"]["nominal_capacity"]
solar_capex = parameters["solar"]["capex"]                  
solar_opex = parameters["solar"]["opex"]                    
solar_subsidy_share = parameters["solar"]["subsidy"]        
solar_lifetime = parameters["solar"]["lifetime"]            

# Extract Battery params  
battery_nominal_capacity = parameters["battery"]["nominal_capacity"]  
battery_capex = parameters["battery"]["capex"]                      
battery_opex = parameters["battery"]["opex"]                        
battery_lifetime = parameters["battery"]["lifetime"]               
η_charge = parameters["battery"]["efficiency"]["charge"]            
η_discharge = parameters["battery"]["efficiency"]["discharge"]      
SOC_min = parameters["battery"]["SOC"]["min"]                       
SOC_max = parameters["battery"]["SOC"]["max"]                       
SOC_0 = parameters["battery"]["SOC"]["initial"]                     
t_charge = parameters["battery"]["operation"]["charge_time"]        
t_discharge = parameters["battery"]["operation"]["discharge_time"]  

# Extract Generator params
has_generator = parameters["generator"]["enabled"]
generator_nominal_capacity = parameters["generator"]["nominal_capacity"] 
generator_capex = parameters["generator"]["capex"]                      
generator_opex = parameters["generator"]["opex"]                        
fuel_lhv = parameters["generator"]["fuel_lhv"]                       
fuel_cost = parameters["generator"]["fuel_cost"]                     
generator_efficiency = parameters["generator"]["efficiency"]            
generator_lifetime = parameters["generator"]["lifetime"]                

# Calculate the yearly discount factor
discount_factor = [1 / ((1 + discount_rate) ^ y) for y in 1:project_lifetime]

# Calculate number of replacements for each component
solar_replacements = max(0, floor((project_lifetime - 1) / solar_lifetime))
battery_replacements = max(0, floor((project_lifetime - 1) / battery_lifetime))
if has_generator 
    generator_replacements = max(0, floor((project_lifetime - 1) / generator_lifetime))
end

# Build arrays of valid replacement times (in whole years), up to project_lifetime - 1 ensuring not to index discount_factor past the end.
solar_replacement_years = solar_lifetime : solar_lifetime : Int(floor((project_lifetime - 1) / solar_lifetime) * solar_lifetime)
battery_replacement_years = battery_lifetime : battery_lifetime : Int(floor((project_lifetime - 1) / battery_lifetime) * battery_lifetime)
if has_generator 
    generator_replacement_years = generator_lifetime : generator_lifetime : Int(floor((project_lifetime - 1) / generator_lifetime) * generator_lifetime)
end

# Calculate the salvage fractions for each component based on the last replacement year
last_install_solar = length(solar_replacement_years) == 0 ? 0 : maximum(solar_replacement_years)
unused_solar_life = solar_lifetime - (project_lifetime - last_install_solar)
salvage_solar_fraction = max(0, unused_solar_life / solar_lifetime)

last_install_battery = length(battery_replacement_years) == 0 ? 0 : maximum(battery_replacement_years)
unused_battery_life = battery_lifetime - (project_lifetime - last_install_battery)
salvage_battery_fraction = max(0, unused_battery_life / battery_lifetime)

if has_generator
    last_install_generator = length(generator_replacement_years) == 0 ? 0 : maximum(generator_replacement_years)
    unused_generator_life = generator_lifetime - (project_lifetime - last_install_generator)
    salvage_generator_fraction = max(0, unused_generator_life / generator_lifetime)
end

# Define the time step
Δt = 1 # [hours]
