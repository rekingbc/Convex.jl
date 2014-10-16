import MathProgBase
export solve!

default_model = nothing
if isdir(Pkg.dir("ECOS"))
  using ECOS
  default_model = ECOS.ECOSMathProgModel
end
if isdir(Pkg.dir("SCS"))
  using SCS
  if default_model == nothing
    default_model = SCS.SCSMathProgModel
  end
end

if default_model == nothing
  error("You have neither ECOS.jl nor SCS.jl installed. Must have at least one of these solvers.")
end

# function solve!(problem::Problem, m::MathProgBase.AbstractMathProgModel=SCS.SCSMathProgModel())
function solve!(problem::Problem, m::MathProgBase.AbstractMathProgModel=ECOS.ECOSMathProgModel())

  c, A, b, cones, var_to_ranges = conic_problem(problem)

  if problem.head == :maximize
    c = -c
  end

  # TODO: Fix once MathProgBase has a loadineqproblem!
  # TODO: Get rid of full once c and b are not sparse
  if typeof(m) == ECOS.ECOSMathProgModel
    n = size(A, 2)
    var_cones = (Symbol, UnitRange{Int64})[]
    push!(var_cones, (:Free, 1:n))
    ECOS.loadineqconicproblem!(m, full(c), A, full(b), cones)
    ECOS.optimize!(m)
  elseif typeof(m) == SCS.SCSMathProgModel
    SCS.loadineqconicproblem!(m, full(c), A, full(b), cones)
    SCS.optimize!(m)
  else
    error("model type $(typeof(m)) not recognized")
  end

  try
    y, z = MathProgBase.getconicdual(m)
    problem.solution = Solution(MathProgBase.getsolution(m), y, z, MathProgBase.status(m), MathProgBase.getobjval(m))
  catch
    problem.solution = Solution(MathProgBase.getsolution(m), MathProgBase.status(m), MathProgBase.getobjval(m))
    populate_variables!(problem, var_to_ranges)
  end
  # minimize -> maximize
  if (problem.head == :maximize)
    problem.solution.optval = -problem.solution.optval
  end

  # Populate the problem with the solution
  problem.optval = problem.solution.optval
  problem.status = problem.solution.status
end

function populate_variables!(problem::Problem, var_to_ranges::Dict{Uint64, (Int64, Int64)})
  x = problem.solution.primal
  for (id, (start_index, end_index)) in var_to_ranges
    var = id_to_variables[id]
    sz = var.size
    var.value = reshape(x[start_index:end_index], sz[1], sz[2])
    if sz == (1, 1)
      var.value = var.value[1]
    end
  end
end
