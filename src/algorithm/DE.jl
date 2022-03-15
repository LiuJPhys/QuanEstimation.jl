function update!(opt::ControlOpt, alg::DE, obj, dynamics, output)
    (; max_episode, p_num, ini_population, c, cr, rng) = alg
    ctrl_length = length(dynamics.data.ctrl[1])
    ctrl_num = length(dynamics.data.Hc)
    populations = repeat(dynamics, p_num)

    # initialization
    if length(ini_population) > p_num
        ini_population = [ini_population[i] for i = 1:p_num]
    end
    for pj = 1:length(ini_population)
        populations[pj].data.ctrl =
            [[ini_population[pj][i, j] for j = 1:ctrl_length] for i = 1:ctrl_num]
    end
    if opt.ctrl_bound[1] == -Inf || opt.ctrl_bound[2] == Inf
        for pj = (length(ini_population)+1):p_num
            populations[pj].data.ctrl =
                [[2 * rand(rng) - 1.0 for j = 1:ctrl_length] for i = 1:ctrl_num]
        end
    else
        a = opt.ctrl_bound[1]
        b = opt.ctrl_bound[2]
        for pj = (length(ini_population)+1):p_num
            populations[pj].data.ctrl =
                [[(b - a) * rand(rng) + a for j = 1:ctrl_length] for i = 1:ctrl_num]
        end
    end

    dynamics_copy = set_ctrl(dynamics, [zeros(ctrl_length) for i = 1:ctrl_num])
    f_noctrl, f_comp = objective(obj, dynamics_copy)
    p_fit, p_out = zeros(p_num), zeros(p_num)
    for i = 1:p_num
        p_out[i], p_fit[i] = objective(obj, populations[i])
    end

    set_f!(output, p_out[1])
    set_buffer!(output, dynamics.data.ctrl)
    set_io!(output, f_noctrl, p_out[1])
    show(opt, output, obj)

    idx = 1
    for i = 1:(max_episode-1)
        for pj = 1:p_num
            #mutations
            mut_num = sample(1:p_num, 3, replace = false)
            ctrl_mut = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
            for ci = 1:ctrl_num
                for ti = 1:ctrl_length
                    ctrl_mut[ci][ti] =
                        populations[mut_num[1]].data.ctrl[ci][ti] +
                        c * (
                            populations[mut_num[2]].data.ctrl[ci][ti] -
                            populations[mut_num[3]].data.ctrl[ci][ti]
                        )
                end
            end
            #crossover 
            ctrl_cross = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
            for cj = 1:ctrl_num
                cross_int = sample(1:ctrl_length, 1, replace = false)[1]
                for tj = 1:ctrl_length
                    rand_num = rand(rng)
                    if rand_num <= cr
                        ctrl_cross[cj][tj] = ctrl_mut[cj][tj]
                    else
                        ctrl_cross[cj][tj] = populations[pj].data.ctrl[cj][tj]
                    end
                end
                ctrl_cross[cj][cross_int] = ctrl_mut[cj][cross_int]
            end
            #selection
            bound!(ctrl_cross, opt.ctrl_bound)
            dynamics_cross = set_ctrl(populations[pj], ctrl_cross)
            f_out, f_cross = objective(obj, dynamics_cross)
            if f_cross > p_fit[pj]
                p_fit[pj] = f_cross
                p_out[pj] = f_out
                for ck = 1:ctrl_num
                    for tk = 1:ctrl_length
                        populations[pj].data.ctrl[ck][tk] = ctrl_cross[ck][tk]
                    end
                end
            end
        end
        idx = findmax(p_fit)[2]
        set_f!(output, p_out[idx])
        set_buffer!(output, populations[idx].data.ctrl)
        set_io!(output, p_out[idx], idx)
        show(output, obj)
    end
    set_io!(output, p_out[idx])
end

#### state optimization ####
function update!(Sopt::StateOpt, alg::DE, obj, dynamics)
    (; p_num, ini_population, c, cr, rng) = alg
    dim = length(dynamics.data.ψ0)
    populations = repeat(dynamics, p_num)
    # initialize 
    if length(ini_population) > p_num
        ini_population = [ini_population[i] for i = 1:p_num]
    end

    for pj = 1:length(ini_population)
        populations[pj].data.ψ0 = [ini_population[pj][i] for i = 1:dim]
    end
    for pj = (length(ini_population)+1):p_num
        r_ini = 2 * rand(rng, dim) - ones(dim)
        r = r_ini / norm(r_ini)
        phi = 2 * pi * rand(rng, dim)
        populations[pj].data.ψ0 = [r[i] * exp(1.0im * phi[i]) for i = 1:dim]
    end

    p_fit, p_out = zeros(p_num), zeros(p_num)
    for i = 1:p_num
        p_out[i], p_fit[i] = objective(obj, populations[i])
    end

    show(Sopt, [dynamics.data.ψ0], output, obj, p_out[1])
    output.f_list = [p_out[1]]
    for ei = 1:(max_episode-1)
        for pj = 1:p_num
            #mutations
            mut_num = sample(1:p_num, 3, replace = false)
            state_mut = zeros(ComplexF64, dim)
            for ci = 1:dim
                state_mut[ci] =
                    populations[mut_num[1]].data.ψ0[ci] +
                    c * (
                        populations[mut_num[2]].data.ψ0[ci] -
                        populations[mut_num[3]].data.ψ0[ci]
                    )
            end
            #crossover
            state_cross = zeros(ComplexF64, dim)
            cross_int = sample(1:dim, 1, replace = false)[1]
            for cj = 1:dim
                rand_num = rand(rng)
                if rand_num <= cr
                    state_cross[cj] = state_mut[cj]
                else
                    state_cross[cj] = populations[pj].data.ψ0[cj]
                end
                state_cross[cross_int] = state_mut[cross_int]
            end
            psi_cross = state_cross / norm(state_cross)
            dynamics_cross = set_state(populations[pj], psi_cross)
            f_out, f_cross = objective(obj, dynamics_cross)
            #selection
            if f_cross > p_fit[pj]
                p_fit[pj] = f_cross
                p_out[pj] = f_out
                for ck = 1:dim
                    populations[pj].data.ψ0[ck] = psi_cross[ck]
                end
            end
        end
        idx = findmax(p_fit)[2]
        append!(output.f_list, p_out[idx])
        show([populations[idx].data.ψ0], output, obj, p_out[idx], ei)
    end
    set_f!(output, output.f_list, [populations[idx].data.ψ0])
end

#### projective measurement optimization ####
function update!(Mopt::MeasurementOpt{Projection}, alg::DE, obj, dynamics, output, C)
    (; p_num, ini_population, c, cr, rng) = alg
    dim = size(dynamics.data.ρ0)[1]
    M_num = length(C)

    populations = repeat(C, p_num)
    # initialize 
    if length(ini_population) > p_num
        ini_population = [ini_population[i] for i = 1:p_num]
    end
    for pj = 1:length(ini_population)
        populations[pj].C = [[ini_population[pj][i, j] for j = 1:dim] for i = 1:M_num]
    end
    for pj = (length(ini_population)+1):p_num
        M_tp = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for mi = 1:M_num
            r_ini = 2 * rand(rng, dim) - ones(dim)
            r = r_ini / norm(r_ini)
            phi = 2 * pi * rand(rng, dim)
            M_tp[mi] = [r[i] * exp(1.0im * phi[i]) for i = 1:dim]
        end
        populations[pj].C = [[M_tp[i][j] for j = 1:dim] for i = 1:M_num]
        # orthogonality and normalization 
        populations[pj].C = gramschmidt(populations[pj].C)
    end

    p_fit, p_out = zeros(p_num), zeros(p_num)
    for pj = 1:p_num
        M = [populations[pj].C[i] * (populations[pj].C[i])' for i = 1:M_num]
        obj_copy = set_M(obj, M)
        p_out[pj], p_fit[pj] = objective(obj_copy, dynamics)
    end

    M = [populations[1].C[i] * (populations[1].C[i])' for i = 1:M_num]
    show(Mopt, [M], output, obj, p_out[1])
    output.f_list = [p_out[1]]

    for ei = 1:(max_episode-1)
        for pj = 1:p_num
            #mutations
            mut_num = sample(1:p_num, 3, replace = false)
            M_mut = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
            for ci = 1:M_num
                for ti = 1:dim
                    M_mut[ci][ti] =
                        populations[mut_num[1]].C[ci][ti] +
                        c * (
                            populations[mut_num[2]].C[ci][ti] -
                            populations[mut_num[3]].C[ci][ti]
                        )
                end
            end
            #crossover
            M_cross = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
            for cj = 1:M_num
                cross_int = sample(1:dim, 1, replace = false)[1]
                for tj = 1:dim
                    rand_num = rand(rng)
                    if rand_num <= cr
                        M_cross[cj][tj] = M_mut[cj][tj]
                    else
                        M_cross[cj][tj] = populations[pj].C[cj][tj]
                    end
                end
                M_cross[cj][cross_int] = M_mut[cj][cross_int]
            end
            # orthogonality and normalization 
            M_cross = gramschmidt(M_cross)
            M = [M_cross[i] * (M_cross[i])' for i = 1:M_num]
            obj_cross = set_M(obj, M)
            f_out, f_cross = objective(obj_cross, dynamics)
            #selection
            if f_cross > p_fit[pj]
                p_fit[pj] = f_cross
                p_out[pj] = f_out
                for ck = 1:M_num
                    for tk = 1:dim
                        populations[pj].C[ck][tk] = M_cross[ck][tk]
                    end
                end
            end
        end
        idx = findmax(p_fit)[2]
        append!(output.f_list, p_out[idx])
        M = [populations[idx].C[i] * (populations[idx].C[i])' for i = 1:M_num]
        show([M], output, obj, p_out[idx], ei)
    end
    set_f!(output, output.f_list, [M])
end

#### update the coefficients according to the given basis ####
function update!(
    Mopt::MeasurementOpt{LinearComb},
    alg::DE,
    obj,
    dynamics,
    output,
    POVM_basis,
    M_num,
)
    (; p_num, populations, c, cr, rng) = alg
    dim = size(dynamics.data.ρ0)[1]
    basis_num = length(POVM_basis)
    # initialize 
    B_all = [[zeros(basis_num) for i = 1:M_num] for j = 1:p_num]
    for pj = 1:p_num
        B_all[pj] = [rand(rng, basis_num) for i = 1:M_num]
        B_all[pj] = bound_LC_coeff(B_all[pj])
    end

    p_fit, p_out = zeros(p_num), zeros(p_num)
    for pj = 1:p_num
        M = [sum([B_all[pj][i][j] * POVM_basis[j] for j = 1:basis_num]) for i = 1:M_num]
        obj_copy = set_M(obj, M)
        p_out[pj], p_fit[pj] = objective(obj_copy, dynamics)
    end

    M = [sum([B_all[1][i][j] * POVM_basis[j] for j = 1:basis_num]) for i = 1:M_num]
    f_opt, f_comp = objective(obj::QFIM{SLD}, dynamics)
    obj_POVM = set_M(obj, POVM_basis)
    f_povm, f_comp = objective(obj_POVM, dynamics)
    show(Mopt, [M], output, obj, p_out[1], f_opt, f_povm)

    output.f_list = [p_out[1]]
    for ei = 1:(max_episode-1)
        for pj = 1:p_num
            #mutations
            mut_num = sample(1:p_num, 3, replace = false)
            M_mut = [Vector{Float64}(undef, basis_num) for i = 1:M_num]
            for ci = 1:M_num
                for ti = 1:basis_num
                    M_mut[ci][ti] =
                        B_all[mut_num[1]][ci][ti] +
                        c * (B_all[mut_num[2]][ci][ti] - B_all[mut_num[3]][ci][ti])
                end
            end
            #crossover
            M_cross = [Vector{Float64}(undef, basis_num) for i = 1:M_num]
            for cj = 1:M_num
                cross_int = sample(1:basis_num, 1, replace = false)[1]
                for tj = 1:basis_num
                    rand_num = rand(rng)
                    if rand_num <= cr
                        M_cross[cj][tj] = M_mut[cj][tj]
                    else
                        M_cross[cj][tj] = B_all[pj][cj][tj]
                    end
                end
                M_cross[cj][cross_int] = M_mut[cj][cross_int]
            end

            # normalize the coefficients 
            M_cross = bound_LC_coeff(M_cross)
            M = [sum([M_cross[i][j] * POVM_basis[j] for j = 1:basis_num]) for i = 1:M_num]
            dynamics_cross = set_M(populations[pj], M)
            f_cross = objective(obj, dynamics_cross)
            #selection
            if f_cross > p_fit[pj]
                p_fit[pj] = f_cross
                for ck = 1:M_num
                    for tk = 1:basis_num
                        B_all[pj][ck][tk] = M_cross[ck][tk]
                    end
                end
            end
        end
        idx = findmax(p_fit)[2]
        append!(output.f_list, p_out[idx])
        M = [sum([B_all[idx][i][j] * POVM_basis[j] for j = 1:basis_num]) for i = 1:M_num]
        show([M], output, obj, p_out[idx], ei)
    end
    set_f!(output, output.f_list, [M])
end

#### update the coefficients of the unitary matrix ####
function update!(Mopt::MeasurementOpt{Rotation}, alg::DE, obj, dynamics, output, POVM_basis)
    (; p_num, populations, c, cr, rng) = alg
    Random.seed!(seed)
    dim = size(dynamics.data.ρ0)[1]
    suN = suN_generator(dim)
    Lambda = [Matrix{ComplexF64}(I, dim, dim)]
    append!(Lambda, [suN[i] for i = 1:length(suN)])

    M_num = length(POVM_basis)
    s_all = [zeros(dim * dim) for i = 1:p_num]
    # initialize 
    p_fit, p_out = zeros(p_num), zeros(p_num)
    for pj = 1:p_num
        # generate a rotation matrix randomly
        s_all[pj] = rand(rng, dim * dim)
        U = rotation_matrix(s_all[pj], Lambda)
        M = [U * POVM_basis[i] * U' for i = 1:M_num]
        obj_copy = set_M(obj, M)
        p_out[pj], p_fit[pj] = objective(obj_copy, dynamics)
    end

    U = rotation_matrix(s_all[1], Lambda)
    M = [U * POVM_basis[i] * U' for i = 1:M_num]
    f_opt, f_comp = objective(obj::QFIM{SLD}, dynamics)
    obj_POVM = set_M(obj, POVM_basis)
    f_povm, f_comp = objective(obj_POVM, dynamics)
    show(Mopt, [M], output, obj, p_out[1], f_opt, f_povm)

    output.f_list = [p_out[1]]
    for ei = 1:(max_episode-1)
        for pj = 1:p_num
            #mutations
            mut_num = sample(1:p_num, 3, replace = false)
            M_mut = Vector{Float64}(undef, dim^2)
            for ti = 1:dim^2
                M_mut[ti] =
                    s_all[mut_num[1]][ti] +
                    c * (s_all[mut_num[2]][ti] - s_all[mut_num[3]][ti])
            end

            #crossover
            M_cross = Vector{Float64}(undef, dim^2)
            cross_int = sample(1:dim^2, 1, replace = false)[1]
            for tj = 1:dim^2
                rand_num = rand(rng)
                if rand_num <= cr
                    M_cross[tj] = M_mut[tj]
                else
                    M_cross[tj] = s_all[pj][tj]
                end
            end
            M_cross[cross_int] = M_mut[cross_int]

            # normalize the coefficients 
            M_cross = bound_rot_coeff(M_cross)
            U = rotation_matrix(M_cross, Lambda)
            M = [U * POVM_basis[i] * U' for i = 1:M_num]
            obj_cross = set_M(obj, M)
            f_out, f_cross = objective(obj_cross, dynamics)
            #selection
            if f_cross > p_fit[pj]
                p_fit[pj] = f_cross
                p_out[pj] = f_out
                for tk = 1:dim^2
                    s_all[pj][tk] = M_cross[tk]
                end
            end
        end
        idx = findmax(p_fit)[2]
        append!(output.f_list, p_out[idx])
        U = rotation_matrix(s_all[idx], Lambda)
        M = [U * POVM_basis[i] * U' for i = 1:M_num]
        show([M], output, obj, p_out[idx], ei)
    end
    set_f!(output, output.f_list, [M])
end

#### state and control optimization ####
function update!(Comopt::StateControlOpt, alg::DE, obj, dynamics)
    (; p_num, populations, c, cr) = alg
    for pj = 1:p_num
        #mutations
        mut_num = sample(1:p_num, 3, replace = false)
        state_mut = zeros(ComplexF64, dim)
        for ci = 1:dim
            state_mut[ci] =
                populations[mut_num[1]].psi[ci] +
                c * (populations[mut_num[2]].psi[ci] - populations[mut_num[3]].psi[ci])
        end

        ctrl_mut = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for ci = 1:ctrl_num
            for ti = 1:ctrl_length
                ctrl_mut[ci][ti] =
                    populations[mut_num[1]].ctrl[ci][ti] +
                    c * (
                        populations[mut_num[2]].ctrl[ci][ti] -
                        populations[mut_num[3]].ctrl[ci][ti]
                    )
            end
        end

        #crossover
        state_cross = zeros(ComplexF64, dim)
        cross_int1 = sample(1:dim, 1, replace = false)[1]
        for cj = 1:dim
            rand_num = rand(rng)
            if rand_num <= cr
                state_cross[cj] = state_mut[cj]
            else
                state_cross[cj] = populations[pj].psi[cj]
            end
            state_cross[cross_int1] = state_mut[cross_int1]
        end
        psi_cross = state_cross / norm(state_cross)

        ctrl_cross = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for cj = 1:ctrl_num
            cross_int2 = sample(1:ctrl_length, 1, replace = false)[1]
            for tj = 1:ctrl_length
                rand_num = rand(rng)
                if rand_num <= cr
                    ctrl_cross[cj][tj] = ctrl_mut[cj][tj]
                else
                    ctrl_cross[cj][tj] = populations[pj].ctrl[cj][tj]
                end
            end
            ctrl_cross[cj][cross_int2] = ctrl_mut[cj][cross_int2]
        end
        bound!(ctrl_cross, populations[pj].ctrl_bound)

        dynamics_cross = set_state_ctrl(populations[pj], psi_cross, ctrl_cross)
        f_cross = objective(obj, dynamics_cross)
        #selection
        if f_cross > p_fit[pj]
            p_fit[pj] = f_cross
            for ck = 1:dim
                populations[pj].psi[ck] = psi_cross[ck]
            end

            for ck = 1:ctrl_num
                for tk = 1:ctrl_length
                    populations[pj].ctrl[ck][tk] = ctrl_cross[ck][tk]
                end
            end
        end
    end
end

#### state and measurement optimization ####
function update!(Comopt::StateMeasurementOpt, alg::DE, obj, dynamics)
    (; p_num, populations, c, cr) = alg
    for pj = 1:p_num
        #mutations
        mut_num = sample(1:p_num, 3, replace = false)
        state_mut = zeros(ComplexF64, dim)
        for ci = 1:dim
            state_mut[ci] =
                populations[mut_num[1]].psi[ci] +
                c * (populations[mut_num[2]].psi[ci] - populations[mut_num[3]].psi[ci])
        end

        M_mut = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for ci = 1:M_num
            for ti = 1:dim
                M_mut[ci][ti] =
                    populations[mut_num[1]].C[ci][ti] +
                    c *
                    (populations[mut_num[2]].C[ci][ti] - populations[mut_num[3]].C[ci][ti])
            end
        end

        #crossover
        state_cross = zeros(ComplexF64, dim)
        cross_int1 = sample(1:dim, 1, replace = false)[1]
        for cj = 1:dim
            rand_num = rand(rng)
            if rand_num <= cr
                state_cross[cj] = state_mut[cj]
            else
                state_cross[cj] = populations[pj].psi[cj]
            end
            state_cross[cross_int1] = state_mut[cross_int1]
        end
        psi_cross = state_cross / norm(state_cross)

        M_cross = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for cj = 1:M_num
            cross_int = sample(1:dim, 1, replace = false)[1]
            for tj = 1:dim
                rand_num = rand(rng)
                if rand_num <= cr
                    M_cross[cj][tj] = M_mut[cj][tj]
                else
                    M_cross[cj][tj] = populations[pj].C[cj][tj]
                end
            end
            M_cross[cj][cross_int] = M_mut[cj][cross_int]
        end
        # orthogonality and normalization 
        M_cross = gramschmidt(M_cross)
        M = [M_cross[i] * (M_cross[i])' for i = 1:M_num]
        dynamics_cross = set_state_M(populations[pj], psi_cross, M)
        f_cross = objective(obj, dynamics_cross)
        #selection
        if f_cross > p_fit[pj]
            p_fit[pj] = f_cross
            for ck = 1:dim
                populations[pj].psi[ck] = psi_cross[ck]
            end

            for ck = 1:M_num
                for tk = 1:dim
                    populations[pj].C[ck][tk] = M_cross[ck][tk]
                end
            end
        end
    end
end

#### control and measurement optimization ####
function update!(Comopt::ControlMeasurementOpt, alg::DE, obj, dynamics)
    (; p_num, populations, c, cr) = alg
    for pj = 1:p_num
        #mutations
        mut_num = sample(1:p_num, 3, replace = false)
        ctrl_mut = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for ci = 1:ctrl_num
            for ti = 1:ctrl_length
                ctrl_mut[ci][ti] =
                    populations[mut_num[1]].ctrl[ci][ti] +
                    c * (
                        populations[mut_num[2]].ctrl[ci][ti] -
                        populations[mut_num[3]].ctrl[ci][ti]
                    )
            end
        end

        M_mut = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for ci = 1:M_num
            for ti = 1:dim
                M_mut[ci][ti] =
                    populations[mut_num[1]].C[ci][ti] +
                    c *
                    (populations[mut_num[2]].C[ci][ti] - populations[mut_num[3]].C[ci][ti])
            end
        end

        #crossover   
        ctrl_cross = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for cj = 1:ctrl_num
            cross_int2 = sample(1:ctrl_length, 1, replace = false)[1]
            for tj = 1:ctrl_length
                rand_num = rand(rng)
                if rand_num <= cr
                    ctrl_cross[cj][tj] = ctrl_mut[cj][tj]
                else
                    ctrl_cross[cj][tj] = populations[pj].ctrl[cj][tj]
                end
            end
            ctrl_cross[cj][cross_int2] = ctrl_mut[cj][cross_int2]
        end
        bound!(ctrl_cross, populations[pj].ctrl_bound)

        M_cross = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for cj = 1:M_num
            cross_int = sample(1:dim, 1, replace = false)[1]
            for tj = 1:dim
                rand_num = rand(rng)
                if rand_num <= cr
                    M_cross[cj][tj] = M_mut[cj][tj]
                else
                    M_cross[cj][tj] = populations[pj].C[cj][tj]
                end
            end
            M_cross[cj][cross_int] = M_mut[cj][cross_int]
        end
        # orthogonality and normalization 
        M_cross = gramschmidt(M_cross)
        M = [M_cross[i] * (M_cross[i])' for i = 1:M_num]
        dynamics_cross = set_ctrl_M(populations[pj], ctrl_cross, M)
        f_cross = objective(obj, dynamics_cross)
        #selection
        if f_cross > p_fit[pj]
            p_fit[pj] = f_cross

            for ck = 1:ctrl_num
                for tk = 1:ctrl_length
                    populations[pj].ctrl[ck][tk] = ctrl_cross[ck][tk]
                end
            end

            for ck = 1:M_num
                for tk = 1:dim
                    populations[pj].C[ck][tk] = M_cross[ck][tk]
                end
            end
        end
    end
end

#### state, control and measurement optimization ####
function update!(Comopt::StateControlMeasurementOpt, alg::DE, obj, dynamics)
    (; p_num, populations, c, cr) = alg
    for pj = 1:p_num
        #mutations
        mut_num = sample(1:p_num, 3, replace = false)
        state_mut = zeros(ComplexF64, dim)
        for ci = 1:dim
            state_mut[ci] =
                populations[mut_num[1]].psi[ci] +
                c * (populations[mut_num[2]].psi[ci] - populations[mut_num[3]].psi[ci])
        end

        ctrl_mut = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for ci = 1:ctrl_num
            for ti = 1:ctrl_length
                ctrl_mut[ci][ti] =
                    populations[mut_num[1]].ctrl[ci][ti] +
                    c * (
                        populations[mut_num[2]].ctrl[ci][ti] -
                        populations[mut_num[3]].ctrl[ci][ti]
                    )
            end
        end

        M_mut = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for ci = 1:M_num
            for ti = 1:dim
                M_mut[ci][ti] =
                    populations[mut_num[1]].C[ci][ti] +
                    c *
                    (populations[mut_num[2]].C[ci][ti] - populations[mut_num[3]].C[ci][ti])
            end
        end

        #crossover
        state_cross = zeros(ComplexF64, dim)
        cross_int1 = sample(1:dim, 1, replace = false)[1]
        for cj = 1:dim
            rand_num = rand(rng)
            if rand_num <= cr
                state_cross[cj] = state_mut[cj]
            else
                state_cross[cj] = populations[pj].psi[cj]
            end
            state_cross[cross_int1] = state_mut[cross_int1]
        end
        psi_cross = state_cross / norm(state_cross)

        ctrl_cross = [Vector{Float64}(undef, ctrl_length) for i = 1:ctrl_num]
        for cj = 1:ctrl_num
            cross_int2 = sample(1:ctrl_length, 1, replace = false)[1]
            for tj = 1:ctrl_length
                rand_num = rand(rng)
                if rand_num <= cr
                    ctrl_cross[cj][tj] = ctrl_mut[cj][tj]
                else
                    ctrl_cross[cj][tj] = populations[pj].ctrl[cj][tj]
                end
            end
            ctrl_cross[cj][cross_int2] = ctrl_mut[cj][cross_int2]
        end
        bound!(ctrl_cross, populations[pj].ctrl_bound)

        M_cross = [Vector{ComplexF64}(undef, dim) for i = 1:M_num]
        for cj = 1:M_num
            cross_int = sample(1:dim, 1, replace = false)[1]
            for tj = 1:dim
                rand_num = rand(rng)
                if rand_num <= cr
                    M_cross[cj][tj] = M_mut[cj][tj]
                else
                    M_cross[cj][tj] = populations[pj].C[cj][tj]
                end
            end
            M_cross[cj][cross_int] = M_mut[cj][cross_int]
        end
        # orthogonality and normalization 
        M_cross = gramschmidt(M_cross)
        M = [M_cross[i] * (M_cross[i])' for i = 1:M_num]
        dynamics_cross = set_state_M(populations[pj], psi_cross, ctrl_cross, M)
        f_cross = objective(obj, dynamics_cross)
        #selection
        if f_cross > p_fit[pj]
            p_fit[pj] = f_cross
            for ck = 1:dim
                populations[pj].psi[ck] = psi_cross[ck]
            end

            for ck = 1:ctrl_num
                for tk = 1:ctrl_length
                    populations[pj].ctrl[ck][tk] = ctrl_cross[ck][tk]
                end
            end

            for ck = 1:M_num
                for tk = 1:dim
                    populations[pj].C[ck][tk] = M_cross[ck][tk]
                end
            end
        end
    end
end
