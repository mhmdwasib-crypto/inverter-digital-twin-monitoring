%% Parameters_Inverter.m
%% ------------------------------------------------------------
% 1. Rated power case selection
% ------------------------------------------------------------
if ~exist('ratedPowerCase','var')
    ratedPowerCase = '9000W';
end

if isstring(ratedPowerCase)
    ratedPowerCase = char(ratedPowerCase);
end

switch ratedPowerCase
    case '6750W'
        P_rated = 6750;
    case '7460W'
        P_rated = 7460;
    case '9000W'
        P_rated = 9000;
    otherwise
        error("Use ratedPowerCase = 6750W, 7460W, or 9000W");
end

%% ------------------------------------------------------------
% 2. Confirmed / available controller parameters
% ------------------------------------------------------------
eta_inv = 0.97;              % inverter efficiency
eta_mppt = 0.99;             % MPPT efficiency

inv_eta = 1 / eta_inv;       % useful for Simulink gain blocks
eta_total_target = eta_inv;
eta_inverter_percent = eta_inv * 100;

Vmppt_min = 660;             % VDC
Vmppt_max = 850;             % VDC

%% ------------------------------------------------------------
% 3. PV module and string estimate
% ------------------------------------------------------------
% Gautam Solar G2X530-HAD values
PV_module_Pmax = 530;        % W
PV_module_Vmp  = 41.50;      % V
PV_module_Voc  = 49.05;      % V
PV_module_Imp  = 12.77;      % A
PV_module_Isc  = 13.65;      % A, estimated / online module family value

% Temperature coefficients
PV_temp_coeff_Pmax = -0.0039;   % per degC
PV_temp_coeff_Voc  = -0.0030;   % per degC
PV_temp_coeff_Isc  =  0.0006;   % per degC

% 19S1P gives about 10.07 kWp and Vmp inside the MPPT range
PV_Ns = 19;
PV_Np = 1;

PV_array_Pmax_calc = PV_Ns * PV_Np * PV_module_Pmax;
PV_string_Vmp = PV_Ns * PV_module_Vmp;
PV_string_Voc = PV_Ns * PV_module_Voc;
PV_string_Imp = PV_Np * PV_module_Imp;
PV_string_Isc = PV_Np * PV_module_Isc;

PV_Voc_10C = PV_string_Voc * (1 + PV_temp_coeff_Voc * (10 - 25));
PV_Voc_0C  = PV_string_Voc * (1 + PV_temp_coeff_Voc * (0 - 25));

PV_array_power = 10000;      % W, rounded site array size

%% ------------------------------------------------------------
% 4. DC-side inverter estimates
% ------------------------------------------------------------
ESR_dc_healthy = 0.05;       % ohm, healthy DC-link ESR
ESR_dc_fault   = 0.20;       % ohm, degraded capacitor ESR
ESR_dc = ESR_dc_healthy;

Vdc_nom = 800;               % V
Vdc_max = 950;               % V
Cdc = 680e-6;                % F

%% ------------------------------------------------------------
% 5. Switching and control parameters
% ------------------------------------------------------------
fsw = 5000;                  % Hz
m_ref = 0.885;
m_max = 0.95;

% aliases in case blocks use alternate names
f_sw = fsw;

%% ------------------------------------------------------------
% 6. Output filter estimates
% ------------------------------------------------------------
L_filter = 2e-3;             % H
R_filter = 0.01;             % ohm

%% ------------------------------------------------------------
% 7. Thermal and loss model parameters
% ------------------------------------------------------------
Tamb = 25;                   % degC

Rth_system = 0.08;           % degC/W
tau_th = 60;                 % seconds

n_switches = 6;

Rth_jc_hotspot = 0.18;       % degC/W
tau_jc_hotspot = 8;          % seconds

Rth_jc = 0.15;               % degC/W
Cth_jc = 25;                 % J/degC
tau_jc = Rth_jc * Cth_jc;

Rth_ch = 0.05;               % degC/W
Cth_ch = 80;                 % J/degC
tau_ch = Rth_ch * Cth_ch;

Rth_ha = 0.04;               % degC/W
Cth_ha = 800;                % J/degC
tau_ha = Rth_ha * Cth_ha;

T_warn = 70;                 % degC
T_fault = 85;                % degC

%% ------------------------------------------------------------
% 8. Residual thresholds
% ------------------------------------------------------------
P_res_warn = 500;            % W
P_res_fault = 1000;          % W

V_res_warn = 20;             % V
V_res_fault = 40;            % V

I_res_warn = 2;              % A
I_res_fault = 4;             % A

T_res_warn = 8;              % degC
T_res_fault = 15;            % degC

% aliases for blocks/scripts that use these names
P_warn_th = P_res_warn;
P_fault_th = P_res_fault;
V_warn_th = V_res_warn;
V_fault_th = V_res_fault;
I_warn_th = I_res_warn;
I_fault_th = I_res_fault;
T_warn_th = T_res_warn;
T_fault_th = T_res_fault;

score_warn_th = 0.5;
score_fault_th = 1.0;

%% ------------------------------------------------------------
% 9. Simulation settings
% ------------------------------------------------------------
Ts_power = 5e-6;             % power electronics sample time
Ts_data = 0.01;              % validation/replay signal sample time

if ~exist('tEnd','var')
    tEnd = 10;
end

t = (0:Ts_data:tEnd)';

%% ------------------------------------------------------------
% 10. AC-side motor-pump equivalent load model
% ------------------------------------------------------------
Vll_rated = 415;             % V line-line
fout_ref = 50;               % Hz

pump_HP = 10;
HP_to_W = 745.7;
P_pump_mech = pump_HP * HP_to_W;

P_load_rated = P_rated;

motor_eff_est = P_pump_mech / P_load_rated;

pump_head_m = 30;
pump_discharge_L_per_day = 315000;
rho_water = 1000;
g_const = 9.81;

pump_flow_m3s = (pump_discharge_L_per_day/1000) / (24*3600);
P_hydraulic_est = rho_water * g_const * pump_flow_m3s * pump_head_m;

pf_assumed = 0.85;

if ~exist('loadCase','var')
    loadCase = 'rated';
end

if isstring(loadCase)
    loadCase = char(loadCase);
end

switch loadCase
    case 'low'
        loadFactor_profile = 0.70 * ones(size(t));
        pf_profile = 0.82 * ones(size(t));

    case 'mid'
        loadFactor_profile = 0.85 * ones(size(t));
        pf_profile = 0.85 * ones(size(t));

    case 'high'
        loadFactor_profile = 1.00 * ones(size(t));
        pf_profile = 0.88 * ones(size(t));

    case 'rated'
        loadFactor_profile = 1.00 * ones(size(t));
        pf_profile = pf_assumed * ones(size(t));

    otherwise
        error("Use loadCase = rated, low, mid, or high");
end

P_load_profile = P_load_rated .* loadFactor_profile;
Q_load_profile = P_load_profile .* tan(acos(pf_profile));
I_load_profile = P_load_profile ./ (sqrt(3) .* Vll_rated .* pf_profile);

P_load_for_sim = P_load_profile(end);
Q_load_for_sim = Q_load_profile(end);
I_load_for_sim = I_load_profile(end);
pf_load_for_sim = pf_profile(end);
loadFactor_for_sim = loadFactor_profile(end);

Q_rated = Q_load_for_sim;
I_rated_calc = I_load_for_sim;
I_rated = I_rated_calc;

P_load_ts = timeseries(P_load_profile,t);
Q_load_ts = timeseries(Q_load_profile,t);
I_load_ts = timeseries(I_load_profile,t);
pf_load_ts = timeseries(pf_profile,t);
loadFactor_ts = timeseries(loadFactor_profile,t);

% aliases in case blocks use alternate names
V_ll_rms = Vll_rated;
PF = pf_load_for_sim;
f_out = fout_ref;

%% ------------------------------------------------------------
% 10B. Display / validation filter initial values
% ------------------------------------------------------------
Tavg_power_plot = 0.005;
alpha_power_plot = Ts_power / (Tavg_power_plot + Ts_power);

P_output_init = P_load_for_sim;
P_input_init = P_output_init / eta_inv;
P_loss_init = P_input_init - P_output_init;
P_loss_nominal = P_loss_init;

%% ------------------------------------------------------------
% 11. Averaged MPPT / DC-link interface parameters
% ------------------------------------------------------------
Vdc_target = 800;
Vdc_min = 660;
Vdc_max_cmd = 850;

D_min = 0.02;
D_max = 0.08;

%% ------------------------------------------------------------
% 12. Final PV Array + Averaged MPPT model
% ------------------------------------------------------------
G = 1000 * ones(size(t));
Tcell = 35 * ones(size(t));

Ppv_available = PV_array_Pmax_calc .* (G/1000) .* ...
    (1 + PV_temp_coeff_Pmax .* (Tcell - 25));

Vpv_mpp = PV_string_Vmp .* ...
    (1 + PV_temp_coeff_Voc .* (Tcell - 25));

Ipv_mpp = Ppv_available ./ max(Vpv_mpp,1);

D_mppt = 1 - (Vpv_mpp ./ Vdc_target);

D_mppt(D_mppt < D_min) = D_min;
D_mppt(D_mppt > D_max) = D_max;

Vdc_cmd = Vpv_mpp ./ (1 - D_mppt);
Vdc_cmd = min(max(Vdc_cmd, Vdc_min), Vdc_max_cmd);

Pdc_demand = P_load_profile / eta_inv;
power_ratio = min(Ppv_available ./ Pdc_demand, 1);

Vdc_cmd = Vdc_cmd .* (0.90 + 0.10 * power_ratio);

Vpv_raw = Vdc_cmd;

Vpv_raw_ts = timeseries(Vpv_raw,t);
Vdc_cmd_ts = timeseries(Vdc_cmd,t);
Vpv_mpp_ts = timeseries(Vpv_mpp,t);
Ipv_mpp_ts = timeseries(Ipv_mpp,t);
D_mppt_ts = timeseries(D_mppt,t);
G_ts = timeseries(G,t);
Tcell_ts = timeseries(Tcell,t);
Ppv_available_ts = timeseries(Ppv_available,t);

%% ------------------------------------------------------------
% 13. Final replay/scenario measured inputs
% ------------------------------------------------------------
if ~exist('faultCase','var')
    faultCase = 'healthy';
end

if isstring(faultCase)
    faultCase = char(faultCase);
end

if exist('t_fault','var')
    faultStart = t_fault;
else
    faultStart = 2;
end

FaultEnable = zeros(size(t));
FaultEnable(t >= faultStart) = 1;
FaultEnable_ts = timeseries(FaultEnable,t);

P_meas_base = 1.0222 * P_load_for_sim;
V_meas_base = 310;
I_meas_base = 1.0183 * I_load_for_sim;
T_meas_base = 27;

P_meas = P_meas_base * ones(size(t));
V_meas = V_meas_base * ones(size(t));
I_meas = I_meas_base * ones(size(t));
T_meas = T_meas_base * ones(size(t));

ESR_dc = ESR_dc_healthy;

switch faultCase

    case 'healthy'
        % no fault

    case 'power'
        P_meas(t >= faultStart) = 0.815 * P_meas_base;

    case 'voltage'
        V_meas(t >= faultStart) = 230;

    case 'current'
        I_meas(t >= faultStart) = 1.47 * I_meas_base;

    case 'thermal'
        T_meas(t >= faultStart) = 70;

    case 'capacitor'
        % capacitor fault is injected using ESR_dc_ts below
        ESR_dc = ESR_dc_healthy;

    case 'sensor_drift_voltage'
        drift = linspace(0,30,sum(t >= faultStart))';
        V_meas(t >= faultStart) = V_meas_base + drift;

    case 'open_switch_proxy'
        I_meas(t >= faultStart) = 0.65 * I_meas_base;
        P_meas(t >= faultStart) = 0.70 * P_meas_base;

    otherwise
        error("Unknown faultCase. Use healthy, power, voltage, current, thermal, capacitor, sensor_drift_voltage, or open_switch_proxy.");
end

%% ------------------------------------------------------------
% 14. Capacitor ESR / health injection signal
% ------------------------------------------------------------
ESR_dc_vec = ESR_dc_healthy * ones(size(t));

if strcmp(faultCase,'capacitor')
    ESR_dc_vec(t >= faultStart) = ESR_dc_fault;
end

ESR_dc_ts = timeseries(ESR_dc_vec, t);
ESR_dc_ts.Name = 'ESR_dc_ts';

ESR_dc = ESR_dc_vec(end);

capHealth_vec = 1 - ((ESR_dc_vec - ESR_dc_healthy) ./ ...
    (ESR_dc_fault - ESR_dc_healthy));

capHealth_vec = min(max(capHealth_vec, 0), 1);

capHealth_ts = timeseries(capHealth_vec, t);
capHealth_ts.Name = 'capHealth_ts';

capHealth = capHealth_vec(end);

ESR_dc_final = ESR_dc;
capHealth_final = capHealth;

P_meas_ts = timeseries(P_meas,t);
V_meas_ts = timeseries(V_meas,t);
I_meas_ts = timeseries(I_meas,t);
T_meas_ts = timeseries(T_meas,t);

P_meas_ts.Name = 'P_meas_ts';
V_meas_ts.Name = 'V_meas_ts';
I_meas_ts.Name = 'I_meas_ts';
T_meas_ts.Name = 'T_meas_ts';

%% ------------------------------------------------------------
% 15. Simple prediction signals for scopes/checking if needed
% ------------------------------------------------------------
P_pred_base = 8812;
V_pred_base = 305;
I_pred_base = I_load_for_sim;
T_est_base = 28.09;

P_pred = P_pred_base * ones(size(t));
V_pred = V_pred_base * ones(size(t));
I_pred = I_pred_base * ones(size(t));
T_est = T_est_base * ones(size(t));

P_pred_ts = timeseries(P_pred,t);
V_pred_ts = timeseries(V_pred,t);
I_pred_ts = timeseries(I_pred,t);
T_est_ts = timeseries(T_est,t);

P_pred_ts.Name = 'P_pred_ts';
V_pred_ts.Name = 'V_pred_ts';
I_pred_ts.Name = 'I_pred_ts';
T_est_ts.Name = 'T_est_ts';

%% ------------------------------------------------------------
% 16. Steady-state validation reference values
% ------------------------------------------------------------
Vdc_validation = 791.9;       % V
Idc_validation = 11.48;       % A
Pdc_validation = Vdc_validation * Idc_validation;
Pac_validation = 8812;        % W
Ploss_validation = Pdc_validation - Pac_validation;
eta_validation = Pac_validation / Pdc_validation;

%% ------------------------------------------------------------
% 17. Expected output for checking
% ------------------------------------------------------------
switch faultCase
    case 'healthy'
        expectedFaultCode = 0;
        expectedFaultName = 'Healthy';
    case 'power'
        expectedFaultCode = 1;
        expectedFaultName = 'Power mismatch';
    case 'voltage'
        expectedFaultCode = 2;
        expectedFaultName = 'Voltage/DC-link fault';
    case 'current'
        expectedFaultCode = 3;
        expectedFaultName = 'Current/load fault';
    case 'thermal'
        expectedFaultCode = 4;
        expectedFaultName = 'Thermal fault';
    case 'capacitor'
        expectedFaultCode = 5;
        expectedFaultName = 'Capacitor degradation';
    case 'sensor_drift_voltage'
        expectedFaultCode = 2;
        expectedFaultName = 'Voltage sensor drift';
    case 'open_switch_proxy'
        expectedFaultCode = 1;
        expectedFaultName = 'Open-switch proxy';
end

%% ------------------------------------------------------------
% 18. Quick calculated values for checking
% ------------------------------------------------------------
PV_summary = table( ...
    PV_array_Pmax_calc, ...
    PV_string_Vmp, ...
    PV_string_Voc, ...
    PV_Voc_10C, ...
    PV_Voc_0C, ...
    Vdc_cmd(end), ...
    D_mppt(end), ...
    Ppv_available(end), ...
    'VariableNames', {'ArrayPower_W','StringVmp_V','StringVoc25C_V', ...
    'StringVoc10C_V','StringVoc0C_V','VdcCmdFinal_V','DmpptFinal', ...
    'PpvAvailableFinal_W'} ...
);

Load_summary = table( ...
    P_rated, ...
    pump_HP, ...
    P_pump_mech, ...
    motor_eff_est, ...
    pump_head_m, ...
    pump_discharge_L_per_day, ...
    P_hydraulic_est, ...
    P_load_for_sim, ...
    Q_load_for_sim, ...
    I_load_for_sim, ...
    pf_load_for_sim, ...
    loadFactor_for_sim, ...
    'VariableNames', {'P_rated_W','Pump_HP','PumpMechanical_W', ...
    'MotorEfficiency_est','PumpHead_m','PumpDischarge_L_per_day', ...
    'HydraulicPower_est_W','P_load_W','Q_load_VAR','I_load_A', ...
    'PF_load','LoadFactor'} ...
);
