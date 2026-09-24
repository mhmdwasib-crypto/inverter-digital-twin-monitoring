% Run one selected fault case for Inverter_Model.slx
% Example:
% faultCase = 'power'; RUN_ONE_FAULT

if ~exist('faultCase','var')
    faultCase = 'healthy';
end

if isstring(faultCase)
    faultCase = char(faultCase);
end

modelName = 'Inverter_Model';
ratedPowerCase = '9000W';
loadCase = 'rated';
tEnd = 10;
t_fault = 2;

Parameters_Inverter;

fprintf('\nRunning model: %s\n', modelName);
fprintf('Fault case: %s\n', faultCase);
fprintf('Fault starts at: %.2f s\n', t_fault);
fprintf('Expected fault code: %d (%s)\n\n', expectedFaultCode, expectedFaultName);

fprintf('Input check:\n');
fprintf('P_meas: %.2f -> %.2f W\n', P_meas(1), P_meas(end));
fprintf('V_meas: %.2f -> %.2f V\n', V_meas(1), V_meas(end));
fprintf('I_meas: %.2f -> %.2f A\n', I_meas(1), I_meas(end));
fprintf('T_meas: %.2f -> %.2f degC\n', T_meas(1), T_meas(end));
fprintf('ESR: %.3f -> %.3f ohm\n', ESR_dc_vec(1), ESR_dc_vec(end));
fprintf('capHealth: %.3f -> %.3f\n\n', capHealth_vec(1), capHealth_vec(end));

if ~isfile([modelName '.slx']) && ~isfile([modelName '.mdl'])
    warning('Inverter_Model.slx is not in the current MATLAB folder.');
end

if ~bdIsLoaded(modelName)
    load_system(modelName);
end

open_system(modelName);

simOut = sim(modelName, ...
    'StopTime', num2str(tEnd), ...
    'ReturnWorkspaceOutputs','on');

[diagFinal, scoreFinal] = read_logs(simOut);

if ~isempty(diagFinal)
    fprintf('\nFinal diagnostic display:\n');
    fprintf('WarningFlag: %.0f\n', diagFinal(1));
    fprintf('FaultFlag:   %.0f\n', diagFinal(2));
    fprintf('FaultCode:   %.0f\n', diagFinal(3));
    fprintf('Severity:    %.1f %%\n', diagFinal(4));
else
    fprintf('\nCould not read diagnosticSummary_log. Check the model display/scope directly.\n');
end

if ~isempty(scoreFinal)
    fprintf('\nFinal fault scores:\n');
    fprintf('Power:     %.3f\n', scoreFinal(1));
    fprintf('Voltage:   %.3f\n', scoreFinal(2));
    fprintf('Current:   %.3f\n', scoreFinal(3));
    fprintf('Thermal:   %.3f\n', scoreFinal(4));
    fprintf('Capacitor: %.3f\n', scoreFinal(5));
else
    fprintf('\nCould not read faultScores_log. Check the fault score display/scope directly.\n');
end

fprintf('\nSimulation finished. Check the Simulink fault displays and scopes.\n');

%% ------------------------------------------------------------
function [diagFinal, scoreFinal] = read_logs(simOut)

diagFinal = [];
scoreFinal = [];

try
    logsout = simOut.get('logsout');
catch
    logsout = [];
end

try
    elem = logsout.get('diagnosticSummary_log');
    data = squeeze(elem.Values.Data);
    if size(data,1) == 4 && size(data,2) ~= 4
        data = data';
    end
    diagFinal = data(end,:);
catch
end

try
    elem = logsout.get('faultScores_log');
    data = squeeze(elem.Values.Data);
    if size(data,1) == 5 && size(data,2) ~= 5
        data = data';
    end
    scoreFinal = data(end,:);
catch
end

end
