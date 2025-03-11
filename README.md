# GridVille Mini-Grid Optimization Model

## Overview

The project provides a tool designed to optimize the sizing and dispatch of a hybrid renewable energy system. It determines the optimal capacities for solar PV, battery storage, and, if enabled, a backup generator. The optimization aims to minimize the **Net Present Cost (NPC)** over the project lifetime while ensuring operational feasibility and maintaining constraints on investment limits, renewable penetration, and energy reliability.

## Features

- **System Sizing:** Determines the required capacity for solar PV, batteries, and backup generators.
- **Unit Committment:** Allows solutions to be integer (units of nominal capacity) for a more realistic sizing. 
- **Dispatch Optimization:** Ensures an optimal operation strategy to meet the energy demand at every time step.
- **Techno-Economic Modeling:** Considers capital expenditures (CAPEX), operational costs (OPEX), subsidies, and discounted replacement costs.
- **Renewable Energy Integration:** Allows setting a minimum renewable share constraint.
- **Lost Load Management:** Enforces a maximum allowable lost load to ensure system reliability.
- **Flexible Parameter Configuration:** Users can modify all settings using a structured YAML configuration file.
- **Time-Series Data Support:** Reads energy demand and solar production profiles from CSV input files.
- **Results Export:** Generates an optimized dispatch schedule for further analysis.

## Folder Structure

- **Programming Language:** Julia
- **Optimization Framework:** JuMP
- **Default Solver:** GLPK
- **Project Organization:**
  - `core/` contains the optimization scripts and utility functions.
  - `inputs/` stores time-series data for load and solar generation and parameters.yaml file for model settings and parameters initialization.
  - `results/` contains the output from the optimization.
  - `Project.toml` and `Manifest.toml` manage package dependencies.

### **Solver**  

> 📌 **Note:**  
> The default solver used in this model is **GLPK**, which is open-source. While GLPK is freely available and suitable for small to medium-scale problems, it can be slow for large-scale optimizations. Depending on the complexity of the model, solving times may range from a few seconds to several minutes. For instance, running a Standalone PV-Battery System (without generator) allowing for unit committment (computationally intensive) requires around 15 minuts. 

> ⚡ **Performance Tip:**  
> For improved performance, alternative solvers can be used such as **Gurobi**. Gurobi is a high-performance commercial solver that significantly improves computation times for large-scale mixed-integer optimization problems. A valid Gurobi license is required, which can be obtained for academic or commercial use. To use Gurobi, install the solver package, ensure the license is configured, and update the script to set Gurobi as the solver.  

> ⚠ **Important:**  
> While Gurobi provides the best computational efficiency, it is not free for commercial applications. Users should select a solver based on their problem size, performance requirements, and licensing availability.  

## Running the Model

### **Step 1: Install Julia**  

Download and install Julia from the official website:  
[Julia Downloads](https://julialang.org/downloads/)  

Ensure that Julia is correctly installed by opening a terminal or command prompt and running:  
``
julia --version
``

This should return the installed Julia version.

### **Step 2: Set Up the Environment**  

#### **Clone the Repository (Optional)**
If the project is hosted on a Git repository, clone it using:

``
git clone https://github.com/your-repo/GridVille.git
``

Then, navigate to the project directory:

``
    cd GridVille
``


#### **Activate the Julia Environment**
Open Julia and activate the environment:

``
    using Pkg Pkg.activate(".") Pkg.instantiate()
``

- `activate(".")` ensures Julia loads the environment from the current directory.
- `instantiate()` installs all required dependencies listed in `Project.toml`.

If any package issues arise, update dependencies using:

``
    Pkg.update()
``

### **Step 3: Open the Project in an IDE**  

#### **Using VS Code (Recommended)**
1. Install [Visual Studio Code](https://code.visualstudio.com/) and the **Julia extension**.
2. Open the GridVille project folder in VS Code.
3. Start the Julia REPL inside VS Code by opening the command palette (`Ctrl+Shift+P` on Windows/Linux or `Cmd+Shift+P` on macOS) and searching for "Start Julia REPL."

### Step 4: Configure Parameters

The model settings are defined in the `parameters.yaml` file. Users can adjust:
- Project duration, discount rate, and currency.
- Investment and operational costs for solar PV, battery storage, and the generator.
- Operational constraints such as maximum CAPEX, lost load limit, and minimum renewable energy share.
- Solver settings to adjust computational performance.

### Step 5: Run the Optimization Model

Execute the model by running the main script `core/main.jl`. The solver will optimize the system based on the defined constraints and objective function.

### Step 6: View and Analyze Results

After execution, the results will be stored in the `results/` folder. The optimized dispatch can be analyzed using spreadsheet software or data visualization tools.

## Example Scenarios

### Standalone PV-Battery System

By disabling the generator in the parameter file, the model optimizes a fully renewable system using only solar PV and batteries.

### Hybrid PV-Battery-Generator System

Enabling the generator allows the model to balance renewable generation with fossil-fuel backup, enforcing a renewable penetration constraint to limit generator reliance.

