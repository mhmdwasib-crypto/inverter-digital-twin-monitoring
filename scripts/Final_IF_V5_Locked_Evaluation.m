%% FINAL IF V5 - LOCKED FINAL TEST
%
% Digital Twin Development for Replay-Based Monitoring of Inverter
%

%
% LOCKED CONFIGURATION:
%
%   Window length        = 60 s
%   Update step          = 10 s
%   Isolation trees      = 300
%   Feature set          = 41 features
%   Feature weighting    = TARGETED
%   Persistence          = 3-of-5
%   Threshold            = 99th percentile of separate
%                          healthy calibration scores
%
% DATA PARTITION:
%
%   0    - 5400 s     TRAINING
%   5400 - 6750 s     THRESHOLD CALIBRATION
%   6750 - 8100 s     DEVELOPMENT / TUNING
%   8100 - 10800 s    FINAL TEST
%
% IMPORTANT:
%
% The 6750-8100 s development period is NOT used for final fitting.
%
% The final 8100-10800 s period is evaluated only after all
% hyperparameters have been locked.
%
% FINAL TEST SCENARIO:
%
%   8100 - 9900 s      unseen healthy lead-in
%   9900 - 10800 s     fault/degradation interval
%
% Gradual capacitor degradation and voltage drift therefore evolve
% over approximately 900 seconds (15 minutes).
%
% The script:
%
%   - evaluates five pre-declared Isolation Forest seeds,
%   - reports mean +/- standard deviation,
%   - does NOT choose the best seed,
%   - evaluates all seven anomaly cases,
%   - calculates confirmed healthy false alarms,
%   - calculates realistic online detection latency,
%   - reports early-warning information for capacitor and voltage drift.
%
% After this script:
%   DO NOT tune parameters using these final-test results.

clear;
clc;
close all;

format short g;

fprintf('\n============================================================\n'); %[output:0cadf5f6]
fprintf(' FINAL IF V5 - LOCKED UNTOUCHED FINAL TEST\n'); %[output:0dca90db]
fprintf('============================================================\n'); %[output:0a15b8a3]


%% ============================================================
% 1. LOCKED CONFIGURATION
% ============================================================

windowLength = 60;          % seconds
stepSize = 10;              % seconds

nTrees = 300;

persistenceMode = '3of5';

thresholdPercentile = 0.99;

forestSeeds = ...
    [101 303 505 707 909];

nSeeds = numel(forestSeeds);

fprintf('\n====================================\n'); %[output:3dd39a95]
fprintf('LOCKED IF CONFIGURATION\n'); %[output:60670df0]
fprintf('====================================\n'); %[output:7865d55e]

fprintf('Window length        : %d s\n',windowLength); %[output:5a48e27b]
fprintf('Step size            : %d s\n',stepSize); %[output:5bfd3c12]
fprintf('Trees                : %d\n',nTrees); %[output:6d4e0281]
fprintf('Weighting            : targeted\n'); %[output:9904480d]
fprintf('Persistence          : %s\n',persistenceMode); %[output:394994e2]
fprintf('Threshold percentile : %.2f %%n', ... %[output:group:55c5458a] %[output:41c09699]
    thresholdPercentile*100); %[output:group:55c5458a] %[output:41c09699]

fprintf('Forest seeds         : '); %[output:02d16c2b]
fprintf('%d ',forestSeeds); %[output:24481880]
fprintf('\n');


%% ============================================================
% 2. LOAD VERIFIED DATA
% ============================================================

dataFile = ...
    'HealthyIFRaw_3hr_LoadV2.csv';

if ~isfile(dataFile)

    error( ...
        'Required file not found: %s', ...
        dataFile);

end

HealthyIFRaw = ...
    readtable(dataFile);

fprintf('\n====================================\n'); %[output:4788bde1]
fprintf('DATASET\n'); %[output:37277a6b]
fprintf('====================================\n'); %[output:5184a9e0]

fprintf('Rows       : %d\n', ... %[output:group:00edc624] %[output:3dd5c631]
    height(HealthyIFRaw)); %[output:group:00edc624] %[output:3dd5c631]

fprintf('Columns    : %d\n', ... %[output:group:5edef631] %[output:39f07dff]
    width(HealthyIFRaw)); %[output:group:5edef631] %[output:39f07dff]

fprintf('Start      : %.0f s\n', ... %[output:group:85cf4f86] %[output:9f8da4a2]
    HealthyIFRaw.tIF(1)); %[output:group:85cf4f86] %[output:9f8da4a2]

fprintf('End        : %.0f s\n', ... %[output:group:1c016bad] %[output:2078e02c]
    HealthyIFRaw.tIF(end)); %[output:group:1c016bad] %[output:2078e02c]

fprintf('Duration   : %.3f h\n', ... %[output:group:59943c4b] %[output:8238e9f6]
    (HealthyIFRaw.tIF(end)- ... %[output:8238e9f6]
     HealthyIFRaw.tIF(1))/3600); %[output:group:59943c4b] %[output:8238e9f6]

dt = ...
    diff(HealthyIFRaw.tIF);

fprintf('Median dt  : %.3f s\n', ... %[output:group:5554551e] %[output:04f3eca3]
    median(dt)); %[output:group:5554551e] %[output:04f3eca3]


%% ============================================================
% 3. REQUIRED VARIABLE CHECK
% ============================================================

requiredVariables = {
    'tIF'
    'loadFactor_if'
    'pf_if'
    'P_load_if'
    'Q_load_if'
    'I_load_if'
    'Vpv_mpp_if'
    'Ipv_mpp_if'
    'Vdc_cmd_if'
    'D_mppt_if'
    'Ppv_available_if'
    'P_meas_if'
    'P_pred_if'
    'V_meas_if'
    'V_pred_if'
    'I_meas_if'
    'I_pred_if'
    'T_meas_if'
    'T_case_if'
    'T_junction_if'
    'absP_if'
    'absV_if'
    'absI_if'
    'absT_if'
    'P_loss_if'
    'capHealth_if'
    };

missingVariables = ...
    setdiff( ...
    requiredVariables, ...
    HealthyIFRaw.Properties.VariableNames);

if ~isempty(missingVariables)

    fprintf('\nMissing variables:\n');

    disp(missingVariables');

    error( ...
        'Required variables missing from dataset.');

end


%% ============================================================
% 4. DATA QUALITY CHECK
% ============================================================

numericMask = ...
    varfun( ...
    @isnumeric, ...
    HealthyIFRaw, ...
    'OutputFormat','uniform');

numericData = ...
    table2array( ...
    HealthyIFRaw(:,numericMask));

if any(isnan(numericData),'all')

    error( ...
        'Dataset contains NaN values.');

end

if any(isinf(numericData),'all')

    error( ...
        'Dataset contains Inf values.');

end

fprintf('\nData quality check: PASSED\n'); %[output:2ae5e4c1]


%% ============================================================
% 5. LOCK HEALTHY CAPACITOR-HEALTH UNCERTAINTY REALIZATION
%
% This is exactly the same healthy-capHealth uncertainty method
% used during development.
%
% The random realization is generated ONCE before partitioning.
% ============================================================

rng(30,'twister');

HealthyIFRaw.capHealth_if = ...
    0.985 + ...
    0.015*rand( ...
    height(HealthyIFRaw),1);

HealthyIFRaw.capHealth_if( ...
    HealthyIFRaw.capHealth_if > 1) = 1;

HealthyIFRaw.capHealth_if( ...
    HealthyIFRaw.capHealth_if < 0.95) = 0.95;


%% ============================================================
% 6. FIXED CHRONOLOGICAL PARTITION
% ============================================================

trainEndTime = 5400;

calibrationEndTime = 6750;

developmentEndTime = 8100;


rawTrain = ...
    HealthyIFRaw( ...
    HealthyIFRaw.tIF < ...
    trainEndTime,:);


rawCalibration = ...
    HealthyIFRaw( ...
    HealthyIFRaw.tIF >= ...
    trainEndTime & ...
    HealthyIFRaw.tIF < ...
    calibrationEndTime,:);


rawDevelopment = ...
    HealthyIFRaw( ...
    HealthyIFRaw.tIF >= ...
    calibrationEndTime & ...
    HealthyIFRaw.tIF < ...
    developmentEndTime,:);


rawFinalTest = ...
    HealthyIFRaw( ...
    HealthyIFRaw.tIF >= ...
    developmentEndTime,:);


fprintf('\n====================================\n'); %[output:03ffa78f]
fprintf('FINAL DATA PARTITION\n'); %[output:8fcc3c20]
fprintf('====================================\n'); %[output:4d925d59]

fprintf('Training samples       : %d\n', ... %[output:group:01f82a4c] %[output:0f63b889]
    height(rawTrain)); %[output:group:01f82a4c] %[output:0f63b889]

fprintf('Calibration samples    : %d\n', ... %[output:group:08adf64b] %[output:9ce0540a]
    height(rawCalibration)); %[output:group:08adf64b] %[output:9ce0540a]

fprintf('Development samples    : %d\n', ... %[output:group:206b85be] %[output:94433885]
    height(rawDevelopment)); %[output:group:206b85be] %[output:94433885]

fprintf('FINAL TEST samples     : %d\n', ... %[output:group:3369d346] %[output:0a3d8cae]
    height(rawFinalTest)); %[output:group:3369d346] %[output:0a3d8cae]

fprintf('\nDevelopment data are NOT used for final model fitting.\n'); %[output:32f2560f]


%% ============================================================
% 7. FINAL FAULT START
%
% Final-test period:
%
% 8100 - 10800 = 2700 s
%
% Healthy lead-in:
%
% 8100 - 9900 = 1800 s = 30 min
%
% Fault/degradation:
%
% 9900 - 10800 = 900 s = 15 min
% ============================================================

finalFaultStartTime = 9900;

finalTestEndTime = ...
    rawFinalTest.tIF(end);

finalFaultDuration = ...
    finalTestEndTime - ...
    finalFaultStartTime;


fprintf('\n====================================\n'); %[output:68be5a56]
fprintf('FINAL TEST TIMING\n'); %[output:449c805e]
fprintf('====================================\n'); %[output:4c9291ae]

fprintf('Final test starts    : %.0f s\n', ... %[output:group:6d286cfe] %[output:2c37874f]
    rawFinalTest.tIF(1)); %[output:group:6d286cfe] %[output:2c37874f]

fprintf('Fault starts         : %.0f s\n', ... %[output:group:8c4766f4] %[output:2848fc9f]
    finalFaultStartTime); %[output:group:8c4766f4] %[output:2848fc9f]

fprintf('Final test ends      : %.0f s\n', ... %[output:group:0f76e1a2] %[output:7041773c]
    finalTestEndTime); %[output:group:0f76e1a2] %[output:7041773c]

fprintf('Healthy lead-in      : %.0f s\n', ... %[output:group:780b91e7] %[output:24f29d92]
    finalFaultStartTime - ... %[output:24f29d92]
    rawFinalTest.tIF(1)); %[output:group:780b91e7] %[output:24f29d92]

fprintf('Fault duration       : %.0f s\n', ... %[output:group:2250d4a2] %[output:0b622d7f]
    finalFaultDuration); %[output:group:2250d4a2] %[output:0b622d7f]


%% ============================================================
% 8. BUILD LOCKED HEALTHY FEATURE SETS
% ============================================================

[TrainFeatures,trainWindowStart] = ...
    make_window_features_LoadV2_improved( ...
    rawTrain, ...
    windowLength, ...
    stepSize);


[CalibrationFeatures,calibrationWindowStart] = ...
    make_window_features_LoadV2_improved( ...
    rawCalibration, ...
    windowLength, ...
    stepSize);


[FinalHealthyFeatures,finalHealthyWindowStart] = ...
    make_window_features_LoadV2_improved( ...
    rawFinalTest, ...
    windowLength, ...
    stepSize);


Xtrain = ...
    table2array(TrainFeatures);

Xcalibration = ...
    table2array(CalibrationFeatures);

XfinalHealthy = ...
    table2array(FinalHealthyFeatures);


fprintf('\n====================================\n'); %[output:2b027c16]
fprintf('LOCKED FEATURE SETS\n'); %[output:7261e8f5]
fprintf('====================================\n'); %[output:4d93ed18]

fprintf('Training windows      : %d\n', ... %[output:group:55c24e84] %[output:21490a8d]
    size(Xtrain,1)); %[output:group:55c24e84] %[output:21490a8d]

fprintf('Calibration windows   : %d\n', ... %[output:group:7077b855] %[output:5c975f5a]
    size(Xcalibration,1)); %[output:group:7077b855] %[output:5c975f5a]

fprintf('Final healthy windows : %d\n', ... %[output:group:6014bf2c] %[output:8d1e850c]
    size(XfinalHealthy,1)); %[output:group:6014bf2c] %[output:8d1e850c]

fprintf('Features/window       : %d\n', ... %[output:group:309cbaab] %[output:8ca04a65]
    size(Xtrain,2)); %[output:group:309cbaab] %[output:8ca04a65]


%% ============================================================
% 9. TRAINING-ONLY STANDARDIZATION
% ============================================================

mu = ...
    mean(Xtrain,1);

sigma = ...
    std(Xtrain,0,1);

sigma( ...
    sigma < 1e-9) = 1;


XtrainN = ...
    (Xtrain-mu)./sigma;

XcalibrationN = ...
    (Xcalibration-mu)./sigma;

XfinalHealthyN = ...
    (XfinalHealthy-mu)./sigma;


%% ============================================================
% 10. LOCK TARGETED FEATURE WEIGHTING
% ============================================================

featureNames = ...
    TrainFeatures.Properties.VariableNames;

featureWeights = ...
    ones( ...
    1,numel(featureNames));


%% ------------------------------------------------------------
% Capacitor-degradation features = weight 4
% -------------------------------------------------------------

capacitorFeatures = {
    'mean_capHealth'
    'min_capHealth'
    'capDrop'
    'capDegMean'
    'capDegMax'
    'capDegSlope'
    };

for k = 1:numel(capacitorFeatures)

    idxFeature = ...
        strcmp( ...
        featureNames, ...
        capacitorFeatures{k});

    if any(idxFeature)

        featureWeights( ...
            idxFeature) = 4.0;

    end

end


%% ------------------------------------------------------------
% Voltage-drift features = weight 4
% -------------------------------------------------------------

voltageFeatures = {
    'mean_absV'
    'max_absV'
    'rms_absV'
    'slope_absV'
    };

for k = 1:numel(voltageFeatures)

    idxFeature = ...
        strcmp( ...
        featureNames, ...
        voltageFeatures{k});

    if any(idxFeature)

        featureWeights( ...
            idxFeature) = 4.0;

    end

end


%% ------------------------------------------------------------
% Supporting temporal features = weight 1.5
% -------------------------------------------------------------

supportingFeatures = {
    'slope_absP'
    'slope_absI'
    'slope_absT'
    'residualEnergy'
    };

for k = 1:numel(supportingFeatures)

    idxFeature = ...
        strcmp( ...
        featureNames, ...
        supportingFeatures{k});

    if any(idxFeature)

        featureWeights( ...
            idxFeature) = 1.5;

    end

end


fprintf('\nTargeted feature weighting: LOCKED\n'); %[output:31408669]


%% ============================================================
% 11. DEFINE FINAL ANOMALY CASES
% ============================================================

faultCaseNames = {
    'Power mismatch'
    'Voltage/DC-link'
    'Current/load'
    'Thermal'
    'Capacitor degradation'
    'Sensor drift voltage'
    'Open-switch proxy'
    };


faultCaseIDs = {
    'power'
    'voltage'
    'current'
    'thermal'
    'capacitor'
    'sensor_drift_voltage'
    'open_switch_proxy'
    };


nCases = ...
    numel(faultCaseIDs);

capIdx = 5;

driftIdx = 6;


%% ============================================================
% 12. CREATE FINAL FAULT REALIZATIONS
%
% IMPORTANT:
%
% Use DIFFERENT fixed fault/noise seeds from development.
%
% Development used another realization.
%
% Final fault copies are generated only from the untouched
% 8100-10800 s final-test operating segment.
% ============================================================

rawFinalFaultCases = ...
    cell(nCases,1);


for c = 1:nCases

    rng(1500+c,'twister');

    rawFinalFaultCases{c} = ...
        make_fault_raw_LoadV2( ...
        rawFinalTest, ...
        faultCaseIDs{c}, ...
        finalFaultStartTime);

end


%% ============================================================
% 13. PRE-BUILD FINAL FAULT FEATURES
% ============================================================

FinalFaultFeatureCells = ...
    cell(nCases,1);

FinalFaultStartCells = ...
    cell(nCases,1);


for c = 1:nCases

    [FinalFaultFeatureCells{c}, ...
     FinalFaultStartCells{c}] = ...
        make_window_features_LoadV2_improved( ...
        rawFinalFaultCases{c}, ...
        windowLength, ...
        stepSize);

end


%% ============================================================
% 14. RESULT STORAGE - PER SEED
% ============================================================

SeedHealthyFAR_percent = ...
    zeros(nSeeds,1);

SeedHealthyAlertEpisodesPerHour = ...
    zeros(nSeeds,1);

SeedThreshold = ...
    zeros(nSeeds,1);


SeedDetection_percent = ...
    zeros(nSeeds,nCases);

SeedDetectionDelay_s = ...
    NaN(nSeeds,nCases);

SeedMeanFaultScore = ...
    NaN(nSeeds,nCases);

SeedMaxFaultScore = ...
    NaN(nSeeds,nCases);


SeedCapHealthAtDetection = ...
    NaN(nSeeds,1);

SeedCapTrajectoryAtDetection_percent = ...
    NaN(nSeeds,1);


SeedVoltageDriftAtDetection_V = ...
    NaN(nSeeds,1);


%% ============================================================
% 15. REPRESENTATIVE-SEED STORAGE
%
% Seed 505 is pre-declared as a representative visualization seed.
%
% It is NOT selected because it performs best.
% ============================================================

representativeSeed = 505;

RepresentativeHealthyScores = [];

RepresentativeThreshold = NaN;

RepresentativeFaultScores = ...
    cell(nCases,1);

RepresentativeFaultStarts = ...
    cell(nCases,1);

RepresentativeFaultConfirmed = ...
    cell(nCases,1);


%% ============================================================
% 16. LOCKED FINAL TEST ACROSS FIVE FOREST SEEDS
% ============================================================

fprintf('\n============================================================\n'); %[output:2e648404]
fprintf(' BEGINNING LOCKED FINAL EVALUATION\n'); %[output:2f86e2b1]
fprintf('============================================================\n'); %[output:445b1f57]


for si = 1:nSeeds %[output:group:11690d7e]

    forestSeed = ...
        forestSeeds(si);


    fprintf('\n------------------------------------------------------------\n'); %[output:4a208c4c] %[output:94a11c48] %[output:33aed4c9] %[output:907322d4] %[output:48059a07]
    fprintf('FINAL FOREST SEED: %d\n',forestSeed); %[output:8f5c9435] %[output:74306479] %[output:403c3b49] %[output:410ebd7d] %[output:8ca6723b]
    fprintf('------------------------------------------------------------\n'); %[output:9296808d] %[output:4b4e7e83] %[output:63497c86] %[output:1e6cae17] %[output:5665dd67]


    %% --------------------------------------------------------
    % Train locked 300-tree forest
    % ---------------------------------------------------------

    rng(forestSeed,'twister');


    sampleSize = ...
        min( ...
        256, ...
        size(XtrainN,1));


    maxDepth = ...
        ceil( ...
        log2(sampleSize));


    forest = ...
        train_custom_iforest_weighted( ...
        XtrainN, ...
        nTrees, ...
        sampleSize, ...
        maxDepth, ...
        featureWeights);


    %% --------------------------------------------------------
    % Calibrate threshold ONLY on healthy calibration set
    % ---------------------------------------------------------

    calibrationScores = ...
        score_custom_iforest( ...
        XcalibrationN, ...
        forest, ...
        sampleSize);

    calibrationScores = ...
        calibrationScores(:);


    sortedCalibrationScores = ...
        sort(calibrationScores);


    thresholdIndex = ...
        ceil( ...
        thresholdPercentile * ...
        numel(sortedCalibrationScores));


    thresholdIndex = ...
        min( ...
        max(thresholdIndex,1), ...
        numel(sortedCalibrationScores));


    threshold = ...
        sortedCalibrationScores( ...
        thresholdIndex);


    SeedThreshold(si) = ...
        threshold;


    %% --------------------------------------------------------
    % Evaluate COMPLETELY UNSEEN healthy final-test data
    % ---------------------------------------------------------

    finalHealthyScores = ...
        score_custom_iforest( ...
        XfinalHealthyN, ...
        forest, ...
        sampleSize);

    finalHealthyScores = ...
        finalHealthyScores(:);


    finalHealthyRawFlags = ...
        finalHealthyScores > ...
        threshold;


    finalHealthyConfirmedFlags = ...
        apply_persistence( ...
        finalHealthyRawFlags, ...
        persistenceMode);


    SeedHealthyFAR_percent(si) = ...
        100 * ...
        mean(finalHealthyConfirmedFlags);


    finalTestHours = ...
        (rawFinalTest.tIF(end) - ...
         rawFinalTest.tIF(1))/3600;


    nHealthyAlertEpisodes = ...
        count_alert_episodes( ...
        finalHealthyConfirmedFlags);


    SeedHealthyAlertEpisodesPerHour(si) = ...
        nHealthyAlertEpisodes / ...
        finalTestHours;


    fprintf('Threshold              : %.6f\n', ... %[output:3f500222] %[output:007e81af] %[output:030c4fb5] %[output:7d9df2b8] %[output:3de679e7]
        threshold); %[output:3f500222] %[output:007e81af] %[output:030c4fb5] %[output:7d9df2b8] %[output:3de679e7]

    fprintf('Final healthy FAR      : %.3f %%n', ... %[output:0eecab1d] %[output:2cd93583] %[output:5fa18c59] %[output:1122e710] %[output:73d2f6d7]
        SeedHealthyFAR_percent(si)); %[output:0eecab1d] %[output:2cd93583] %[output:5fa18c59] %[output:1122e710] %[output:73d2f6d7]

    fprintf('Healthy alerts/hour    : %.3f\n', ... %[output:4550962c] %[output:1dee8e36] %[output:9cd5e94f] %[output:4c1abe39] %[output:99b3e498]
        SeedHealthyAlertEpisodesPerHour(si)); %[output:4550962c] %[output:1dee8e36] %[output:9cd5e94f] %[output:4c1abe39] %[output:99b3e498]


    %% --------------------------------------------------------
    % Store representative seed visualization information
    % ---------------------------------------------------------

    if forestSeed == representativeSeed

        RepresentativeHealthyScores = ...
            finalHealthyScores;

        RepresentativeThreshold = ...
            threshold;

    end


    %% ========================================================
    % TEST ALL SEVEN FINAL ANOMALY CASES
    % ========================================================

    for c = 1:nCases

        faultFeatures = ...
            FinalFaultFeatureCells{c};


        faultWindowStart = ...
            FinalFaultStartCells{c}(:);


        Xfault = ...
            table2array( ...
            faultFeatures);


        XfaultN = ...
            (Xfault-mu)./sigma;


        faultScores = ...
            score_custom_iforest( ...
            XfaultN, ...
            forest, ...
            sampleSize);


        faultScores = ...
            faultScores(:);


        rawFlags = ...
            faultScores > ...
            threshold;


        confirmedFlags = ...
            apply_persistence( ...
            rawFlags, ...
            persistenceMode);


        faultWindowEnd = ...
            faultWindowStart + ...
            windowLength;


        %% ----------------------------------------------------
        % Fully post-fault detection rate
        % -----------------------------------------------------

        postFaultIdx = ...
            faultWindowStart >= ...
            finalFaultStartTime;


        if any(postFaultIdx)

            SeedDetection_percent(si,c) = ...
                100 * mean( ...
                confirmedFlags( ...
                postFaultIdx));


            SeedMeanFaultScore(si,c) = ...
                mean( ...
                faultScores( ...
                postFaultIdx));


            SeedMaxFaultScore(si,c) = ...
                max( ...
                faultScores( ...
                postFaultIdx));

        else

            SeedDetection_percent(si,c) = ...
                NaN;

        end


        %% ----------------------------------------------------
        % Online confirmed-alert detection delay
        %
        % A new alert episode must BEGIN after fault onset.
        %
        % Decision time = feature-window END.
        % -----------------------------------------------------

        confirmedRise = ...
            confirmedFlags & ...
            ~[false; ...
            confirmedFlags(1:end-1)];


        eligibleRise = ...
            confirmedRise & ...
            faultWindowEnd > ...
            finalFaultStartTime;


        firstConfirmed = ...
            find( ...
            eligibleRise, ...
            1, ...
            'first');


        if isempty(firstConfirmed)

            SeedDetectionDelay_s(si,c) = ...
                NaN;

        else

            detectionDecisionTime = ...
                faultWindowEnd( ...
                firstConfirmed);


            SeedDetectionDelay_s(si,c) = ...
                detectionDecisionTime - ...
                finalFaultStartTime;


            %% -----------------------------------------------
            % Capacitor early-warning state at detection
            % -----------------------------------------------

            if c == capIdx

                rawCapFault = ...
                    rawFinalFaultCases{c};


                [~,rawIdx] = ...
                    min( ...
                    abs( ...
                    rawCapFault.tIF - ...
                    detectionDecisionTime));


                capHealthAtDetection = ...
                    rawCapFault.capHealth_if( ...
                    rawIdx);


                SeedCapHealthAtDetection(si) = ...
                    capHealthAtDetection;


                initialFaultIndex = ...
                    find( ...
                    rawCapFault.tIF >= ...
                    finalFaultStartTime, ...
                    1, ...
                    'first');


                initialCapHealth = ...
                    rawCapFault.capHealth_if( ...
                    initialFaultIndex);


                finalCapHealth = 0.20;


                denom = ...
                    initialCapHealth - ...
                    finalCapHealth;


                if abs(denom) > 1e-12

                    trajectoryPercent = ...
                        100 * ...
                        (initialCapHealth - ...
                         capHealthAtDetection) / ...
                        denom;


                    trajectoryPercent = ...
                        min( ...
                        max(trajectoryPercent,0), ...
                        100);


                    SeedCapTrajectoryAtDetection_percent(si) = ...
                        trajectoryPercent;

                end

            end


            %% -----------------------------------------------
            % Intended voltage drift at detection
            %
            % Final synthetic ramp:
            %
            % 0 -> +30 V over 900 s
            % -----------------------------------------------

            if c == driftIdx

                driftFraction = ...
                    (detectionDecisionTime - ...
                     finalFaultStartTime) / ...
                    finalFaultDuration;


                driftFraction = ...
                    min( ...
                    max(driftFraction,0), ...
                    1);


                SeedVoltageDriftAtDetection_V(si) = ...
                    30 * ...
                    driftFraction;

            end

        end


        %% ----------------------------------------------------
        % Store representative-seed timelines
        % -----------------------------------------------------

        if forestSeed == representativeSeed

            RepresentativeFaultScores{c} = ...
                faultScores;

            RepresentativeFaultStarts{c} = ...
                faultWindowStart;

            RepresentativeFaultConfirmed{c} = ...
                confirmedFlags;

        end

    end


    %% --------------------------------------------------------
    % Print seed-level gradual fault result
    % ---------------------------------------------------------

    fprintf('\nCapacitor detection    : %.2f %%n', ... %[output:0f1d4de9] %[output:27859cb3] %[output:44ed2218] %[output:84d6f2eb] %[output:608c18a5]
        SeedDetection_percent(si,capIdx)); %[output:0f1d4de9] %[output:27859cb3] %[output:44ed2218] %[output:84d6f2eb] %[output:608c18a5]

    fprintf('Capacitor delay        : %.1f s\n', ... %[output:7f45391c] %[output:678d7a6a] %[output:2405f03d] %[output:3351d7e2] %[output:14c8b0e9]
        SeedDetectionDelay_s(si,capIdx)); %[output:7f45391c] %[output:678d7a6a] %[output:2405f03d] %[output:3351d7e2] %[output:14c8b0e9]

    fprintf('Voltage drift detect   : %.2f %%n', ... %[output:9ebb4ca0] %[output:18943e4d] %[output:145f3dec] %[output:66352597] %[output:29d17210]
        SeedDetection_percent(si,driftIdx)); %[output:9ebb4ca0] %[output:18943e4d] %[output:145f3dec] %[output:66352597] %[output:29d17210]

    fprintf('Voltage drift delay    : %.1f s\n', ... %[output:5b4bb785] %[output:2ec6463d] %[output:1eea5619] %[output:3dc49121] %[output:4d347850]
        SeedDetectionDelay_s(si,driftIdx)); %[output:5b4bb785] %[output:2ec6463d] %[output:1eea5619] %[output:3dc49121] %[output:4d347850]

end %[output:group:11690d7e]


%% ============================================================
% 17. AGGREGATE FINAL RESULTS
% ============================================================

MeanDetection_percent = ...
    mean( ...
    SeedDetection_percent, ...
    1, ...
    'omitnan')';


StdDetection_percent = ...
    std( ...
    SeedDetection_percent, ...
    0, ...
    1, ...
    'omitnan')';


MeanDetectionDelay_s = ...
    mean( ...
    SeedDetectionDelay_s, ...
    1, ...
    'omitnan')';


StdDetectionDelay_s = ...
    std( ...
    SeedDetectionDelay_s, ...
    0, ...
    1, ...
    'omitnan')';


MeanFaultScore = ...
    mean( ...
    SeedMeanFaultScore, ...
    1, ...
    'omitnan')';


MeanMaxFaultScore = ...
    mean( ...
    SeedMaxFaultScore, ...
    1, ...
    'omitnan')';


MeanHealthyFAR_percent = ...
    mean( ...
    SeedHealthyFAR_percent, ...
    'omitnan');


StdHealthyFAR_percent = ...
    std( ...
    SeedHealthyFAR_percent, ...
    'omitnan');


MeanHealthyAlertsPerHour = ...
    mean( ...
    SeedHealthyAlertEpisodesPerHour, ...
    'omitnan');


StdHealthyAlertsPerHour = ...
    std( ...
    SeedHealthyAlertEpisodesPerHour, ...
    'omitnan');


MeanThreshold = ...
    mean(SeedThreshold);


StdThreshold = ...
    std(SeedThreshold);


%% ============================================================
% 18. GRADUAL-FAULT FINAL METRICS
% ============================================================

FinalCapDetectionMean = ...
    MeanDetection_percent(capIdx);

FinalCapDetectionSD = ...
    StdDetection_percent(capIdx);

FinalCapDelayMean = ...
    MeanDetectionDelay_s(capIdx);

FinalCapDelaySD = ...
    StdDetectionDelay_s(capIdx);


FinalDriftDetectionMean = ...
    MeanDetection_percent(driftIdx);

FinalDriftDetectionSD = ...
    StdDetection_percent(driftIdx);

FinalDriftDelayMean = ...
    MeanDetectionDelay_s(driftIdx);

FinalDriftDelaySD = ...
    StdDetectionDelay_s(driftIdx);


FinalBalancedGradualDetection = ...
    min( ...
    FinalCapDetectionMean, ...
    FinalDriftDetectionMean);


FinalMeanGradualDetection = ...
    mean([ ...
    FinalCapDetectionMean, ...
    FinalDriftDetectionMean]);


otherIdx = ...
    [1 2 3 4 7];


FinalOtherFaultMeanDetection = ...
    mean( ...
    MeanDetection_percent(otherIdx), ...
    'omitnan');


MeanCapHealthAtDetection = ...
    mean( ...
    SeedCapHealthAtDetection, ...
    'omitnan');


StdCapHealthAtDetection = ...
    std( ...
    SeedCapHealthAtDetection, ...
    'omitnan');


MeanCapTrajectoryAtDetection_percent = ...
    mean( ...
    SeedCapTrajectoryAtDetection_percent, ...
    'omitnan');


StdCapTrajectoryAtDetection_percent = ...
    std( ...
    SeedCapTrajectoryAtDetection_percent, ...
    'omitnan');


MeanDriftAtDetection_V = ...
    mean( ...
    SeedVoltageDriftAtDetection_V, ...
    'omitnan');


StdDriftAtDetection_V = ...
    std( ...
    SeedVoltageDriftAtDetection_V, ...
    'omitnan');


%% ============================================================
% 19. FINAL FAULT RESULTS TABLE
% ============================================================

FaultCase = ...
    faultCaseNames;


FinalIF_V5_FaultResults = ...
    table( ...
    FaultCase, ...
    MeanDetection_percent, ...
    StdDetection_percent, ...
    MeanDetectionDelay_s, ...
    StdDetectionDelay_s, ...
    MeanFaultScore, ...
    MeanMaxFaultScore, ...
    'VariableNames',{ ...
    'FaultCase', ...
    'MeanDetection_percent', ...
    'StdDetection_percent', ...
    'MeanDetectionDelay_s', ...
    'StdDetectionDelay_s', ...
    'MeanFaultScore', ...
    'MeanMaxFaultScore'});


%% ============================================================
% 20. FINAL PER-SEED TABLE
% ============================================================

Seed = ...
    forestSeeds(:);


FinalIF_V5_PerSeedGradual = ...
    table( ...
    Seed, ...
    SeedThreshold, ...
    SeedHealthyFAR_percent, ...
    SeedHealthyAlertEpisodesPerHour, ...
    SeedDetection_percent(:,capIdx), ...
    SeedDetectionDelay_s(:,capIdx), ...
    SeedCapHealthAtDetection, ...
    SeedCapTrajectoryAtDetection_percent, ...
    SeedDetection_percent(:,driftIdx), ...
    SeedDetectionDelay_s(:,driftIdx), ...
    SeedVoltageDriftAtDetection_V, ...
    'VariableNames',{ ...
    'Seed', ...
    'Threshold', ...
    'HealthyFAR_percent', ...
    'HealthyAlertsPerHour', ...
    'CapDetection_percent', ...
    'CapDelay_s', ...
    'CapHealthAtDetection', ...
    'CapTrajectoryAtDetection_percent', ...
    'DriftDetection_percent', ...
    'DriftDelay_s', ...
    'DriftAtDetection_V'});


%% ============================================================
% 21. PRINT FINAL RESULTS
% ============================================================

fprintf('\n\n============================================================\n'); %[output:2b3f29dc]
fprintf(' FINAL IF V5 - LOCKED FINAL TEST RESULTS\n'); %[output:01f21e53]
fprintf('============================================================\n'); %[output:896a702f]

fprintf('\nLOCKED ARCHITECTURE\n'); %[output:31847d2e]
fprintf('Window              : %d s\n',windowLength); %[output:960955c1]
fprintf('Step                : %d s\n',stepSize); %[output:3d888f56]
fprintf('Trees               : %d\n',nTrees); %[output:0dfa4bd2]
fprintf('Weighting           : targeted\n'); %[output:8b7968ad]
fprintf('Persistence         : %s\n',persistenceMode); %[output:28516d3a]
fprintf('Threshold rule      : 99th percentile healthy calibration\n'); %[output:7b1625db]


fprintf('\nFINAL HEALTHY PERFORMANCE\n'); %[output:3ab837e0]

fprintf('Healthy FAR          : %.3f +/- %.3f %%n', ... %[output:group:6ecf881a] %[output:2e721504]
    MeanHealthyFAR_percent, ... %[output:2e721504]
    StdHealthyFAR_percent); %[output:group:6ecf881a] %[output:2e721504]

fprintf('Alert episodes/hour  : %.3f +/- %.3f\n', ... %[output:group:5d85b332] %[output:31221e56]
    MeanHealthyAlertsPerHour, ... %[output:31221e56]
    StdHealthyAlertsPerHour); %[output:group:5d85b332] %[output:31221e56]

fprintf('Threshold             : %.6f +/- %.6f\n', ... %[output:group:6546bf93] %[output:2c777eaf]
    MeanThreshold, ... %[output:2c777eaf]
    StdThreshold); %[output:group:6546bf93] %[output:2c777eaf]


fprintf('\nFINAL ALL-FAULT RESULTS\n'); %[output:81b356a3]

disp(FinalIF_V5_FaultResults); %[output:6e3954a3]


fprintf('\nFINAL GRADUAL-FAULT PERFORMANCE\n'); %[output:61ae8f6e]

fprintf('Capacitor detection       : %.2f +/- %.2f %%n', ... %[output:group:74beaf0b] %[output:7bd4d143]
    FinalCapDetectionMean, ... %[output:7bd4d143]
    FinalCapDetectionSD); %[output:group:74beaf0b] %[output:7bd4d143]

fprintf('Capacitor delay           : %.1f +/- %.1f s\n', ... %[output:group:04d999f2] %[output:9139ff84]
    FinalCapDelayMean, ... %[output:9139ff84]
    FinalCapDelaySD); %[output:group:04d999f2] %[output:9139ff84]

fprintf('CapHealth at first alert  : %.4f +/- %.4f\n', ... %[output:group:0df1861f] %[output:318db4f2]
    MeanCapHealthAtDetection, ... %[output:318db4f2]
    StdCapHealthAtDetection); %[output:group:0df1861f] %[output:318db4f2]

fprintf('Cap trajectory at alert   : %.1f +/- %.1f %%n', ... %[output:group:518f4f39] %[output:54d5f25e]
    MeanCapTrajectoryAtDetection_percent, ... %[output:54d5f25e]
    StdCapTrajectoryAtDetection_percent); %[output:group:518f4f39] %[output:54d5f25e]


fprintf('\nVoltage drift detection   : %.2f +/- %.2f %%n', ... %[output:group:3f7190ef] %[output:07bb5ac1]
    FinalDriftDetectionMean, ... %[output:07bb5ac1]
    FinalDriftDetectionSD); %[output:group:3f7190ef] %[output:07bb5ac1]

fprintf('Voltage drift delay       : %.1f +/- %.1f s\n', ... %[output:group:5b228e3d] %[output:629f0887]
    FinalDriftDelayMean, ... %[output:629f0887]
    FinalDriftDelaySD); %[output:group:5b228e3d] %[output:629f0887]

fprintf('Drift at first alert      : %.2f +/- %.2f V\n', ... %[output:group:93d4c8b5] %[output:55963fa3]
    MeanDriftAtDetection_V, ... %[output:55963fa3]
    StdDriftAtDetection_V); %[output:group:93d4c8b5] %[output:55963fa3]


fprintf('\nBalanced gradual detect   : %.2f %%n', ... %[output:group:16ce1c93] %[output:457444a4]
    FinalBalancedGradualDetection); %[output:group:16ce1c93] %[output:457444a4]

fprintf('Mean gradual detection    : %.2f %%n', ... %[output:group:8ec06eaf] %[output:2cbf1b71]
    FinalMeanGradualDetection); %[output:group:8ec06eaf] %[output:2cbf1b71]

fprintf('Other-fault mean detect   : %.2f %%n', ... %[output:group:6216f7a0] %[output:8148738c]
    FinalOtherFaultMeanDetection); %[output:group:6216f7a0] %[output:8148738c]


%% ============================================================
% 22. COMPARE VOLTAGE DRIFT TO RULE-BASED WARNING
%
% Existing rule-based voltage residual warning threshold = 20 V.
%
% IMPORTANT:
% This comparison is descriptive only.
% The Isolation Forest does NOT use the rule-based warning flag.
% ============================================================

ruleVoltageWarning_V = 20;


fprintf('\n====================================\n'); %[output:48f4547c]
fprintf('EARLY-WARNING COMPARISON\n'); %[output:1c5c0d41]
fprintf('====================================\n'); %[output:34b9cc8f]

fprintf('Rule-based voltage warning threshold : %.1f V\n', ... %[output:group:5dfb11de] %[output:8aa5dfca]
    ruleVoltageWarning_V); %[output:group:5dfb11de] %[output:8aa5dfca]

fprintf('Mean IF drift at first alert         : %.2f V\n', ... %[output:group:5109405e] %[output:97052050]
    MeanDriftAtDetection_V); %[output:group:5109405e] %[output:97052050]


if isfinite(MeanDriftAtDetection_V) %[output:group:04189d3b]

    if MeanDriftAtDetection_V < ...
            ruleVoltageWarning_V

        fprintf(['Result: IF detected the developing drift before ' ... %[output:0efb37dd]
                 'the 20 V deterministic warning threshold.\n']); %[output:0efb37dd]

    else

        fprintf(['Result: IF did not precede the 20 V deterministic ' ...
                 'warning threshold in the final test.\n']);

    end

end %[output:group:04189d3b]


%% ============================================================
% 23. SAVE FINAL CSV RESULTS
% ============================================================

writetable( ...
    FinalIF_V5_FaultResults, ...
    'FinalIF_V5_LOCKED_FaultResults.csv');


writetable( ...
    FinalIF_V5_PerSeedGradual, ...
    'FinalIF_V5_LOCKED_PerSeedGradualResults.csv');


%% ============================================================
% 24. SAVE LOCKED MODEL / PARAMETERS
% ============================================================

save( ...
    'FinalIF_V5_LOCKED_FinalEvaluation.mat', ...
    'windowLength', ...
    'stepSize', ...
    'nTrees', ...
    'persistenceMode', ...
    'thresholdPercentile', ...
    'forestSeeds', ...
    'featureNames', ...
    'featureWeights', ...
    'mu', ...
    'sigma', ...
    'SeedThreshold', ...
    'FinalIF_V5_FaultResults', ...
    'FinalIF_V5_PerSeedGradual', ...
    'MeanHealthyFAR_percent', ...
    'StdHealthyFAR_percent', ...
    'MeanHealthyAlertsPerHour', ...
    'FinalCapDetectionMean', ...
    'FinalCapDetectionSD', ...
    'FinalCapDelayMean', ...
    'FinalCapDelaySD', ...
    'FinalDriftDetectionMean', ...
    'FinalDriftDetectionSD', ...
    'FinalDriftDelayMean', ...
    'FinalDriftDelaySD', ...
    'FinalBalancedGradualDetection', ...
    'FinalMeanGradualDetection', ...
    'FinalOtherFaultMeanDetection', ...
    'MeanCapHealthAtDetection', ...
    'MeanCapTrajectoryAtDetection_percent', ...
    'MeanDriftAtDetection_V');


%% ============================================================
% 25. SAVE HUMAN-READABLE LOCKED CONFIGURATION
% ============================================================

fid = ...
    fopen( ...
    'FinalIF_V5_LOCKED_Configuration.txt', ...
    'w');


if fid ~= -1

    fprintf(fid, ...
        'FINAL IF V5 LOCKED CONFIGURATION\n');

    fprintf(fid, ...
        '================================\n\n');

    fprintf(fid, ...
        'Window length: %d s\n', ...
        windowLength);

    fprintf(fid, ...
        'Step size: %d s\n', ...
        stepSize);

    fprintf(fid, ...
        'Trees: %d\n', ...
        nTrees);

    fprintf(fid, ...
        'Weighting: targeted\n');

    fprintf(fid, ...
        'Persistence: %s\n', ...
        persistenceMode);

    fprintf(fid, ...
        'Threshold percentile: %.2f %%n', ...
        100*thresholdPercentile);

    fprintf(fid, ...
        'Training interval: 0-5400 s\n');

    fprintf(fid, ...
        'Calibration interval: 5400-6750 s\n');

    fprintf(fid, ...
        'Development interval: 6750-8100 s\n');

    fprintf(fid, ...
        'Final test interval: 8100-10800 s\n');

    fprintf(fid, ...
        'Final fault onset: 9900 s\n');

    fprintf(fid, ...
        'Forest seeds: ');

    fprintf(fid,'%d ',forestSeeds);

    fprintf(fid,'\n');

    fclose(fid);

end


%% ============================================================
% 26. PLOT - FINAL ALL-FAULT DETECTION
% ============================================================

figure;

bar( ...
    MeanDetection_percent);

hold on;


errorbar( ...
    1:nCases, ...
    MeanDetection_percent, ...
    StdDetection_percent, ...
    '.', ...
    'LineWidth',1.2);


xticks(1:nCases);

xticklabels( ...
    faultCaseNames);

xtickangle(30);

ylabel( ...
    'Confirmed detection rate (%)');

ylim([0 105]);

title( ...
    'Final IF V5 - Locked Final Test Detection Rate');

grid on;


saveas( ...
    gcf, ...
    'FinalIF_V5_LOCKED_DetectionRate.png');


%% ============================================================
% 27. PLOT - FINAL DETECTION DELAY
% ============================================================

figure;

bar( ...
    MeanDetectionDelay_s);

hold on;


errorbar( ...
    1:nCases, ...
    MeanDetectionDelay_s, ...
    StdDetectionDelay_s, ...
    '.', ...
    'LineWidth',1.2);


xticks(1:nCases);

xticklabels( ...
    faultCaseNames);

xtickangle(30);

ylabel( ...
    'Confirmed online detection delay (s)');

title( ...
    'Final IF V5 - Locked Final Test Detection Delay');

grid on;


saveas( ...
    gcf, ...
    'FinalIF_V5_LOCKED_DetectionDelay.png');


%% ============================================================
% 28. PLOT - FINAL GRADUAL FAULT PERFORMANCE
% ============================================================

figure;

gradualMeans = [ ...
    FinalCapDetectionMean, ...
    FinalDriftDetectionMean];


gradualSD = [ ...
    FinalCapDetectionSD, ...
    FinalDriftDetectionSD];


bar(gradualMeans);

hold on;


errorbar( ...
    1:2, ...
    gradualMeans, ...
    gradualSD, ...
    '.', ...
    'LineWidth',1.2);


xticks([1 2]);

xticklabels({ ...
    'Capacitor degradation', ...
    'Voltage sensor drift'});


ylabel( ...
    'Confirmed detection rate (%)');

ylim([0 105]);

title( ...
    'Final IF V5 - Gradual Degradation Detection');

grid on;


saveas( ...
    gcf, ...
    'FinalIF_V5_LOCKED_GradualDetection.png');


%% ============================================================
% 29. PLOT - FINAL HEALTHY FAR ACROSS SEEDS
% ============================================================

figure;

bar( ...
    SeedHealthyFAR_percent);


xticks(1:nSeeds);

xticklabels( ...
    string(forestSeeds));


xlabel( ...
    'Isolation Forest seed');

ylabel( ...
    'Confirmed healthy FAR (%)');

title( ...
    'Final IF V5 - Healthy False Alarm Rate Across Seeds');

yline( ...
    1, ...
    '--', ...
    '1% development acceptance target');

grid on;


saveas( ...
    gcf, ...
    'FinalIF_V5_LOCKED_HealthyFAR.png');


%% ============================================================
% 30. PLOT - REPRESENTATIVE HEALTHY SCORE TIMELINE
%
% Seed 505 was declared in advance.
% It is NOT selected based on performance.
% ============================================================

if ~isempty(RepresentativeHealthyScores)

    figure;

    plot( ...
        finalHealthyWindowStart, ...
        RepresentativeHealthyScores, ...
        'LineWidth',1.2);

    hold on;


    yline( ...
        RepresentativeThreshold, ...
        '--', ...
        'Locked threshold');


    xlabel( ...
        'Window start time (s)');

    ylabel( ...
        'Isolation score');

    title( ...
        sprintf( ...
        'Final IF V5 - Unseen Healthy Scores (Seed %d)', ...
        representativeSeed));

    grid on;


    saveas( ...
        gcf, ...
        'FinalIF_V5_LOCKED_HealthyScoreTimeline.png');

end


%% ============================================================
% 31. PLOT - REPRESENTATIVE CAPACITOR SCORE TIMELINE
% ============================================================

if ~isempty( ...
        RepresentativeFaultScores{capIdx})

    figure;

    plot( ...
        RepresentativeFaultStarts{capIdx}, ...
        RepresentativeFaultScores{capIdx}, ...
        'LineWidth',1.2);

    hold on;


    yline( ...
        RepresentativeThreshold, ...
        '--', ...
        'Locked threshold');


    xline( ...
        finalFaultStartTime, ...
        '--', ...
        'Degradation begins');


    xlabel( ...
        'Window start time (s)');

    ylabel( ...
        'Isolation score');

    title( ...
        sprintf( ...
        'Final IF V5 - Capacitor Degradation Score (Seed %d)', ...
        representativeSeed));

    grid on;


    saveas( ...
        gcf, ...
        'FinalIF_V5_LOCKED_CapacitorScoreTimeline.png');

end


%% ============================================================
% 32. PLOT - REPRESENTATIVE VOLTAGE-DRIFT SCORE TIMELINE
% ============================================================

if ~isempty( ...
        RepresentativeFaultScores{driftIdx})

    figure;

    plot( ...
        RepresentativeFaultStarts{driftIdx}, ...
        RepresentativeFaultScores{driftIdx}, ...
        'LineWidth',1.2);

    hold on;


    yline( ...
        RepresentativeThreshold, ...
        '--', ...
        'Locked threshold');


    xline( ...
        finalFaultStartTime, ...
        '--', ...
        'Voltage drift begins');


    xlabel( ...
        'Window start time (s)');

    ylabel( ...
        'Isolation score');

    title( ...
        sprintf( ...
        'Final IF V5 - Voltage Drift Score (Seed %d)', ...
        representativeSeed));

    grid on;


    saveas( ...
        gcf, ...
        'FinalIF_V5_LOCKED_VoltageDriftScoreTimeline.png');

end


%% ============================================================
% 33. FINAL COMPLETION MESSAGE
% ============================================================

fprintf('\n============================================================\n'); %[output:53e897c5]
fprintf(' FINAL IF V5 LOCKED FINAL TEST COMPLETE\n'); %[output:21cf7716]
fprintf('============================================================\n'); %[output:71487d16]

fprintf('\nCreated:\n'); %[output:4312186b]

fprintf(' FinalIF_V5_LOCKED_FaultResults.csv\n'); %[output:17e4be76]

fprintf(' FinalIF_V5_LOCKED_PerSeedGradualResults.csv\n'); %[output:11b789f7]

fprintf(' FinalIF_V5_LOCKED_FinalEvaluation.mat\n'); %[output:74f4f230]

fprintf(' FinalIF_V5_LOCKED_Configuration.txt\n'); %[output:52cd0755]

fprintf(' FinalIF_V5_LOCKED_DetectionRate.png\n'); %[output:2f535889]

fprintf(' FinalIF_V5_LOCKED_DetectionDelay.png\n'); %[output:992db42f]

fprintf(' FinalIF_V5_LOCKED_GradualDetection.png\n'); %[output:8f95bc03]

fprintf(' FinalIF_V5_LOCKED_HealthyFAR.png\n'); %[output:6ccce8c1]

fprintf(' FinalIF_V5_LOCKED_HealthyScoreTimeline.png\n'); %[output:99909891]

fprintf(' FinalIF_V5_LOCKED_CapacitorScoreTimeline.png\n'); %[output:2f8b5336]

fprintf(' FinalIF_V5_LOCKED_VoltageDriftScoreTimeline.png\n'); %[output:80f8f4e1]


fprintf('\n============================================================\n'); %[output:7d95ecc8]
fprintf(' IMPORTANT\n'); %[output:19641b80]
fprintf('============================================================\n'); %[output:8154f1fd]

fprintf(['These are FINAL simulation/replay test results for the ' ... %[output:group:45ca3ddd] %[output:23220896]
         'locked architecture.\n']); %[output:group:45ca3ddd] %[output:23220896]

fprintf(['Do NOT modify IF hyperparameters based on these final-test ' ... %[output:group:6592e9c1] %[output:7ad6a8a9]
         'results.\n']); %[output:group:6592e9c1] %[output:7ad6a8a9]

fprintf(['Smart SIP field data, when available, will constitute a ' ... %[output:group:5760fb10] %[output:551336b1]
         'separate field-calibration/validation stage.\n']); %[output:group:5760fb10] %[output:551336b1]


%% ============================================================
%% LOCAL FUNCTIONS
%% ============================================================


function [FeatureTable,startTimes] = ...
    make_window_features_LoadV2_improved( ...
    raw,windowLength,stepSize)

    t = ...
        raw.tIF;


    if (t(end)-t(1)) < ...
            windowLength

        error( ...
            'Data segment shorter than requested window.');

    end


    startTimes = ...
        (t(1): ...
         stepSize: ...
         (t(end)-windowLength))';


    nW = ...
        numel(startTimes);


    FeatureMatrix = ...
        zeros(nW,41);


    for w = 1:nW

        idx = ...
            t >= startTimes(w) & ...
            t < startTimes(w)+ ...
            windowLength;


        x = ...
            raw(idx,:);


        if height(x) < 2

            error( ...
                'Window contains fewer than two samples.');

        end


        capDeg = ...
            1-x.capHealth_if;


        capDrop = ...
            x.capHealth_if(1) - ...
            x.capHealth_if(end);


        residualEnergy = ...
            mean( ...
            x.absP_if/1000 + ...
            x.absV_if/40 + ...
            x.absI_if/4 + ...
            x.absT_if/15);


        FeatureMatrix(w,:) = [ ...
            ...
            mean(x.absP_if), ...
            max(x.absP_if), ...
            std(x.absP_if), ...
            sqrt(mean(x.absP_if.^2)), ...
            ...
            mean(x.absV_if), ...
            max(x.absV_if), ...
            std(x.absV_if), ...
            sqrt(mean(x.absV_if.^2)), ...
            ...
            mean(x.absI_if), ...
            max(x.absI_if), ...
            std(x.absI_if), ...
            sqrt(mean(x.absI_if.^2)), ...
            ...
            mean(x.absT_if), ...
            max(x.absT_if), ...
            std(x.absT_if), ...
            sqrt(mean(x.absT_if.^2)), ...
            ...
            mean(x.T_case_if), ...
            mean(x.T_junction_if), ...
            mean(x.P_loss_if), ...
            mean(x.capHealth_if), ...
            ...
            mean(x.Vpv_mpp_if), ...
            mean(x.Ipv_mpp_if), ...
            mean(x.Vdc_cmd_if), ...
            mean(x.D_mppt_if), ...
            mean(x.Ppv_available_if), ...
            ...
            mean(x.P_load_if), ...
            mean(x.Q_load_if), ...
            mean(x.I_load_if), ...
            mean(x.loadFactor_if), ...
            mean(x.pf_if), ...
            ...
            min(x.capHealth_if), ...
            capDrop, ...
            mean(capDeg), ...
            max(capDeg), ...
            simple_slope(capDeg), ...
            ...
            simple_slope(x.absP_if), ...
            simple_slope(x.absV_if), ...
            simple_slope(x.absI_if), ...
            simple_slope(x.absT_if), ...
            ...
            max(x.T_junction_if), ...
            residualEnergy ...
            ];

    end


    featureNames = {
        'mean_absP'
        'max_absP'
        'std_absP'
        'rms_absP'
        'mean_absV'
        'max_absV'
        'std_absV'
        'rms_absV'
        'mean_absI'
        'max_absI'
        'std_absI'
        'rms_absI'
        'mean_absT'
        'max_absT'
        'std_absT'
        'rms_absT'
        'mean_Tcase'
        'mean_Tjunction'
        'mean_Ploss'
        'mean_capHealth'
        'mean_Vpv'
        'mean_Ipv'
        'mean_Vdc'
        'mean_Dmppt'
        'mean_PpvAvailable'
        'mean_Pload'
        'mean_Qload'
        'mean_Iload'
        'mean_loadFactor'
        'mean_pf'
        'min_capHealth'
        'capDrop'
        'capDegMean'
        'capDegMax'
        'capDegSlope'
        'slope_absP'
        'slope_absV'
        'slope_absI'
        'slope_absT'
        'max_Tjunction'
        'residualEnergy'
        };


    featureNames = ...
        featureNames';


    FeatureTable = ...
        array2table( ...
        FeatureMatrix, ...
        'VariableNames', ...
        featureNames);

end


function s = ...
    simple_slope(y)

    y = ...
        y(:);

    n = ...
        numel(y);


    if n < 2

        s = 0;

        return;

    end


    x = ...
        (0:n-1)';


    x = ...
        x-mean(x);

    y = ...
        y-mean(y);


    denominator = ...
        sum(x.^2);


    if denominator < ...
            1e-12

        s = 0;

    else

        s = ...
            sum(x.*y) / ...
            denominator;

    end

end


function confirmed = ...
    apply_persistence(flags,mode)

    flags = ...
        logical(flags(:));

    n = ...
        numel(flags);

    confirmed = ...
        false(n,1);


    switch mode

        case '3of5'

            for i = 5:n

                confirmed(i) = ...
                    sum( ...
                    flags(i-4:i)) >= 3;

            end


        case '2of3'

            for i = 3:n

                confirmed(i) = ...
                    sum( ...
                    flags(i-2:i)) >= 2;

            end


        otherwise

            error( ...
                'Unknown persistence mode: %s', ...
                mode);

    end

end


function nEpisodes = ...
    count_alert_episodes(flags)

    flags = ...
        logical(flags(:));


    rises = ...
        flags & ...
        ~[false; ...
        flags(1:end-1)];


    nEpisodes = ...
        sum(rises);

end


function rawFault = ...
    make_fault_raw_LoadV2( ...
    raw,faultCase,faultStartTime)

    rawFault = ...
        raw;


    idx = ...
        rawFault.tIF >= ...
        faultStartTime;


    nFault = ...
        sum(idx);


    if nFault < 1

        error( ...
            'No samples exist after fault onset.');

    end


    switch faultCase


        case 'power'

            rawFault.P_meas_if(idx) = ...
                0.815 * ...
                rawFault.P_pred_if(idx) + ...
                50*randn(nFault,1);


        case 'voltage'

            rawFault.V_meas_if(idx) = ...
                rawFault.V_pred_if(idx) - ...
                75 + ...
                1.5*randn(nFault,1);


        case 'current'

            rawFault.I_meas_if(idx) = ...
                1.47 * ...
                rawFault.I_pred_if(idx) + ...
                0.10*randn(nFault,1);


        case 'thermal'

            rawFault.T_meas_if(idx) = ...
                70 + ...
                0.8*randn(nFault,1);


        case 'capacitor'

            firstFaultSample = ...
                find( ...
                idx, ...
                1, ...
                'first');


            initialCapHealth = ...
                rawFault.capHealth_if( ...
                firstFaultSample);


            degradation = ...
                linspace( ...
                initialCapHealth, ...
                0.20, ...
                nFault)';


            rawFault.capHealth_if(idx) = ...
                degradation;


        case 'sensor_drift_voltage'

            drift = ...
                linspace( ...
                0, ...
                30, ...
                nFault)';


            rawFault.V_meas_if(idx) = ...
                rawFault.V_pred_if(idx) + ...
                drift + ...
                1.5*randn(nFault,1);


        case 'open_switch_proxy'

            rawFault.P_meas_if(idx) = ...
                0.70 * ...
                rawFault.P_pred_if(idx) + ...
                50*randn(nFault,1);


            rawFault.I_meas_if(idx) = ...
                0.65 * ...
                rawFault.I_pred_if(idx) + ...
                0.10*randn(nFault,1);


        otherwise

            error( ...
                'Unknown fault case: %s', ...
                faultCase);

    end


    %% --------------------------------------------------------
    % Recalculate residuals following final-test injection
    % ---------------------------------------------------------

    rawFault.P_res_if = ...
        rawFault.P_meas_if - ...
        rawFault.P_pred_if;


    rawFault.V_res_if = ...
        rawFault.V_meas_if - ...
        rawFault.V_pred_if;


    rawFault.I_res_if = ...
        rawFault.I_meas_if - ...
        rawFault.I_pred_if;


    rawFault.T_res_if = ...
        rawFault.T_meas_if - ...
        rawFault.T_case_if;


    rawFault.absP_if = ...
        abs(rawFault.P_res_if);


    rawFault.absV_if = ...
        abs(rawFault.V_res_if);


    rawFault.absI_if = ...
        abs(rawFault.I_res_if);


    rawFault.absT_if = ...
        abs(rawFault.T_res_if);

end


function forest = ...
    train_custom_iforest_weighted( ...
    X,nTrees,sampleSize,maxDepth,featureWeights)

    n = ...
        size(X,1);


    forest = ...
        cell(nTrees,1);


    for i = 1:nTrees

        idx = ...
            randperm( ...
            n, ...
            sampleSize);


        Xsample = ...
            X(idx,:);


        forest{i} = ...
            grow_tree_weighted( ...
            Xsample, ...
            0, ...
            maxDepth, ...
            featureWeights);

    end

end


function node = ...
    grow_tree_weighted( ...
    X,depth,maxDepth,featureWeights)

    [n,~] = ...
        size(X);


    if depth >= maxDepth || ...
       n <= 1

        node.type = ...
            'external';

        node.size = ...
            n;

        return;

    end


    ranges = ...
        max(X,[],1) - ...
        min(X,[],1);


    validFeatures = ...
        find( ...
        ranges > 1e-9);


    if isempty(validFeatures)

        node.type = ...
            'external';

        node.size = ...
            n;

        return;

    end


    weights = ...
        featureWeights( ...
        validFeatures);


    weights = ...
        weights / ...
        sum(weights);


    cumulativeWeights = ...
        cumsum(weights);


    r = ...
        rand;


    chosenIdx = ...
        find( ...
        cumulativeWeights >= r, ...
        1, ...
        'first');


    q = ...
        validFeatures( ...
        chosenIdx);


    xmin = ...
        min(X(:,q));


    xmax = ...
        max(X(:,q));


    splitValue = ...
        xmin + ...
        rand * ...
        (xmax-xmin);


    leftIdx = ...
        X(:,q) < ...
        splitValue;


    rightIdx = ...
        ~leftIdx;


    if sum(leftIdx)==0 || ...
       sum(rightIdx)==0

        node.type = ...
            'external';

        node.size = ...
            n;

        return;

    end


    node.type = ...
        'internal';


    node.q = ...
        q;


    node.splitValue = ...
        splitValue;


    node.left = ...
        grow_tree_weighted( ...
        X(leftIdx,:), ...
        depth+1, ...
        maxDepth, ...
        featureWeights);


    node.right = ...
        grow_tree_weighted( ...
        X(rightIdx,:), ...
        depth+1, ...
        maxDepth, ...
        featureWeights);

end


function scores = ...
    score_custom_iforest( ...
    X,forest,sampleSize)

    n = ...
        size(X,1);


    nTrees = ...
        numel(forest);


    pathLengths = ...
        zeros(n,nTrees);


    for i = 1:n

        for tr = 1:nTrees

            pathLengths(i,tr) = ...
                path_length( ...
                X(i,:), ...
                forest{tr}, ...
                0);

        end

    end


    meanPathLength = ...
        mean( ...
        pathLengths, ...
        2);


    c = ...
        c_factor( ...
        sampleSize);


    scores = ...
        2.^( ...
        -meanPathLength ./ ...
        c);

end


function h = ...
    path_length( ...
    x,node,currentDepth)

    if strcmp( ...
            node.type, ...
            'external')

        h = ...
            currentDepth + ...
            c_factor( ...
            node.size);

        return;

    end


    if x(node.q) < ...
            node.splitValue

        h = ...
            path_length( ...
            x, ...
            node.left, ...
            currentDepth+1);

    else

        h = ...
            path_length( ...
            x, ...
            node.right, ...
            currentDepth+1);

    end

end


function c = ...
    c_factor(n)

    if n <= 1

        c = 0;

    elseif n == 2

        c = 1;

    else

        eulerGamma = ...
            0.5772156649;


        c = ...
            2 * ...
            ( ...
            log(n-1) + ...
            eulerGamma ...
            ) - ...
            2*(n-1)/n;

    end

end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":6}
%---
%[output:0cadf5f6]
%   data: {"dataType":"text","outputData":{"text":"\n============================================================\n","truncated":false}}
%---
%[output:0dca90db]
%   data: {"dataType":"text","outputData":{"text":" FINAL IF V5 - LOCKED UNTOUCHED FINAL TEST\n","truncated":false}}
%---
%[output:0a15b8a3]
%   data: {"dataType":"text","outputData":{"text":"============================================================\n","truncated":false}}
%---
%[output:3dd39a95]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:60670df0]
%   data: {"dataType":"text","outputData":{"text":"LOCKED IF CONFIGURATION\n","truncated":false}}
%---
%[output:7865d55e]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:5a48e27b]
%   data: {"dataType":"text","outputData":{"text":"Window length        : 60 s\n","truncated":false}}
%---
%[output:5bfd3c12]
%   data: {"dataType":"text","outputData":{"text":"Step size            : 10 s\n","truncated":false}}
%---
%[output:6d4e0281]
%   data: {"dataType":"text","outputData":{"text":"Trees                : 300\n","truncated":false}}
%---
%[output:9904480d]
%   data: {"dataType":"text","outputData":{"text":"Weighting            : targeted\n","truncated":false}}
%---
%[output:394994e2]
%   data: {"dataType":"text","outputData":{"text":"Persistence          : 3of5\n","truncated":false}}
%---
%[output:41c09699]
%   data: {"dataType":"text","outputData":{"text":"Threshold percentile : 99.00 %n","truncated":false}}
%---
%[output:02d16c2b]
%   data: {"dataType":"text","outputData":{"text":"Forest seeds         : ","truncated":false}}
%---
%[output:24481880]
%   data: {"dataType":"text","outputData":{"text":"101 303 505 707 909 ","truncated":false}}
%---
%[output:4788bde1]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:37277a6b]
%   data: {"dataType":"text","outputData":{"text":"DATASET\n","truncated":false}}
%---
%[output:5184a9e0]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:3dd5c631]
%   data: {"dataType":"text","outputData":{"text":"Rows       : 10801\n","truncated":false}}
%---
%[output:39f07dff]
%   data: {"dataType":"text","outputData":{"text":"Columns    : 29\n","truncated":false}}
%---
%[output:9f8da4a2]
%   data: {"dataType":"text","outputData":{"text":"Start      : 0 s\n","truncated":false}}
%---
%[output:2078e02c]
%   data: {"dataType":"text","outputData":{"text":"End        : 10800 s\n","truncated":false}}
%---
%[output:8238e9f6]
%   data: {"dataType":"text","outputData":{"text":"Duration   : 3.000 h\n","truncated":false}}
%---
%[output:04f3eca3]
%   data: {"dataType":"text","outputData":{"text":"Median dt  : 1.000 s\n","truncated":false}}
%---
%[output:2ae5e4c1]
%   data: {"dataType":"text","outputData":{"text":"\nData quality check: PASSED\n","truncated":false}}
%---
%[output:03ffa78f]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:8fcc3c20]
%   data: {"dataType":"text","outputData":{"text":"FINAL DATA PARTITION\n","truncated":false}}
%---
%[output:4d925d59]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:0f63b889]
%   data: {"dataType":"text","outputData":{"text":"Training samples       : 5400\n","truncated":false}}
%---
%[output:9ce0540a]
%   data: {"dataType":"text","outputData":{"text":"Calibration samples    : 1350\n","truncated":false}}
%---
%[output:94433885]
%   data: {"dataType":"text","outputData":{"text":"Development samples    : 1350\n","truncated":false}}
%---
%[output:0a3d8cae]
%   data: {"dataType":"text","outputData":{"text":"FINAL TEST samples     : 2701\n","truncated":false}}
%---
%[output:32f2560f]
%   data: {"dataType":"text","outputData":{"text":"\nDevelopment data are NOT used for final model fitting.\n","truncated":false}}
%---
%[output:68be5a56]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:449c805e]
%   data: {"dataType":"text","outputData":{"text":"FINAL TEST TIMING\n","truncated":false}}
%---
%[output:4c9291ae]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:2c37874f]
%   data: {"dataType":"text","outputData":{"text":"Final test starts    : 8100 s\n","truncated":false}}
%---
%[output:2848fc9f]
%   data: {"dataType":"text","outputData":{"text":"Fault starts         : 9900 s\n","truncated":false}}
%---
%[output:7041773c]
%   data: {"dataType":"text","outputData":{"text":"Final test ends      : 10800 s\n","truncated":false}}
%---
%[output:24f29d92]
%   data: {"dataType":"text","outputData":{"text":"Healthy lead-in      : 1800 s\n","truncated":false}}
%---
%[output:0b622d7f]
%   data: {"dataType":"text","outputData":{"text":"Fault duration       : 900 s\n","truncated":false}}
%---
%[output:2b027c16]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:7261e8f5]
%   data: {"dataType":"text","outputData":{"text":"LOCKED FEATURE SETS\n","truncated":false}}
%---
%[output:4d93ed18]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:21490a8d]
%   data: {"dataType":"text","outputData":{"text":"Training windows      : 534\n","truncated":false}}
%---
%[output:5c975f5a]
%   data: {"dataType":"text","outputData":{"text":"Calibration windows   : 129\n","truncated":false}}
%---
%[output:8d1e850c]
%   data: {"dataType":"text","outputData":{"text":"Final healthy windows : 265\n","truncated":false}}
%---
%[output:8ca04a65]
%   data: {"dataType":"text","outputData":{"text":"Features\/window       : 41\n","truncated":false}}
%---
%[output:31408669]
%   data: {"dataType":"text","outputData":{"text":"\nTargeted feature weighting: LOCKED\n","truncated":false}}
%---
%[output:2e648404]
%   data: {"dataType":"text","outputData":{"text":"\n============================================================\n","truncated":false}}
%---
%[output:2f86e2b1]
%   data: {"dataType":"text","outputData":{"text":" BEGINNING LOCKED FINAL EVALUATION\n","truncated":false}}
%---
%[output:445b1f57]
%   data: {"dataType":"text","outputData":{"text":"============================================================\n","truncated":false}}
%---
%[output:4a208c4c]
%   data: {"dataType":"text","outputData":{"text":"\n------------------------------------------------------------\n","truncated":false}}
%---
%[output:8f5c9435]
%   data: {"dataType":"text","outputData":{"text":"FINAL FOREST SEED: 101\n","truncated":false}}
%---
%[output:9296808d]
%   data: {"dataType":"text","outputData":{"text":"------------------------------------------------------------\n","truncated":false}}
%---
%[output:3f500222]
%   data: {"dataType":"text","outputData":{"text":"Threshold              : 0.536838\n","truncated":false}}
%---
%[output:0eecab1d]
%   data: {"dataType":"text","outputData":{"text":"Final healthy FAR      : 0.000 %n","truncated":false}}
%---
%[output:4550962c]
%   data: {"dataType":"text","outputData":{"text":"Healthy alerts\/hour    : 0.000\n","truncated":false}}
%---
%[output:0f1d4de9]
%   data: {"dataType":"text","outputData":{"text":"\nCapacitor detection    : 89.41 %n","truncated":false}}
%---
%[output:7f45391c]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay        : 40.0 s\n","truncated":false}}
%---
%[output:9ebb4ca0]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift detect   : 100.00 %n","truncated":false}}
%---
%[output:5b4bb785]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay    : 60.0 s\n","truncated":false}}
%---
%[output:94a11c48]
%   data: {"dataType":"text","outputData":{"text":"\n------------------------------------------------------------\n","truncated":false}}
%---
%[output:33aed4c9]
%   data: {"dataType":"text","outputData":{"text":"\n------------------------------------------------------------\n","truncated":false}}
%---
%[output:907322d4]
%   data: {"dataType":"text","outputData":{"text":"\n------------------------------------------------------------\n","truncated":false}}
%---
%[output:48059a07]
%   data: {"dataType":"text","outputData":{"text":"\n------------------------------------------------------------\n","truncated":false}}
%---
%[output:74306479]
%   data: {"dataType":"text","outputData":{"text":"FINAL FOREST SEED: 303\n","truncated":false}}
%---
%[output:403c3b49]
%   data: {"dataType":"text","outputData":{"text":"FINAL FOREST SEED: 505\n","truncated":false}}
%---
%[output:410ebd7d]
%   data: {"dataType":"text","outputData":{"text":"FINAL FOREST SEED: 707\n","truncated":false}}
%---
%[output:8ca6723b]
%   data: {"dataType":"text","outputData":{"text":"FINAL FOREST SEED: 909\n","truncated":false}}
%---
%[output:4b4e7e83]
%   data: {"dataType":"text","outputData":{"text":"------------------------------------------------------------\n","truncated":false}}
%---
%[output:2ec6463d]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay    : 110.0 s\n","truncated":false}}
%---
%[output:63497c86]
%   data: {"dataType":"text","outputData":{"text":"------------------------------------------------------------\n","truncated":false}}
%---
%[output:1e6cae17]
%   data: {"dataType":"text","outputData":{"text":"------------------------------------------------------------\n","truncated":false}}
%---
%[output:5665dd67]
%   data: {"dataType":"text","outputData":{"text":"------------------------------------------------------------\n","truncated":false}}
%---
%[output:007e81af]
%   data: {"dataType":"text","outputData":{"text":"Threshold              : 0.545797\n","truncated":false}}
%---
%[output:18943e4d]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift detect   : 94.12 %n","truncated":false}}
%---
%[output:030c4fb5]
%   data: {"dataType":"text","outputData":{"text":"Threshold              : 0.530818\n","truncated":false}}
%---
%[output:7d9df2b8]
%   data: {"dataType":"text","outputData":{"text":"Threshold              : 0.536047\n","truncated":false}}
%---
%[output:3de679e7]
%   data: {"dataType":"text","outputData":{"text":"Threshold              : 0.536428\n","truncated":false}}
%---
%[output:2cd93583]
%   data: {"dataType":"text","outputData":{"text":"Final healthy FAR      : 0.000 %n","truncated":false}}
%---
%[output:1eea5619]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay    : 60.0 s\n","truncated":false}}
%---
%[output:678d7a6a]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay        : 40.0 s\n","truncated":false}}
%---
%[output:5fa18c59]
%   data: {"dataType":"text","outputData":{"text":"Final healthy FAR      : 0.000 %n","truncated":false}}
%---
%[output:1122e710]
%   data: {"dataType":"text","outputData":{"text":"Final healthy FAR      : 0.000 %n","truncated":false}}
%---
%[output:73d2f6d7]
%   data: {"dataType":"text","outputData":{"text":"Final healthy FAR      : 0.000 %n","truncated":false}}
%---
%[output:1dee8e36]
%   data: {"dataType":"text","outputData":{"text":"Healthy alerts\/hour    : 0.000\n","truncated":false}}
%---
%[output:27859cb3]
%   data: {"dataType":"text","outputData":{"text":"\nCapacitor detection    : 54.12 %n","truncated":false}}
%---
%[output:9cd5e94f]
%   data: {"dataType":"text","outputData":{"text":"Healthy alerts\/hour    : 0.000\n","truncated":false}}
%---
%[output:145f3dec]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift detect   : 100.00 %n","truncated":false}}
%---
%[output:4c1abe39]
%   data: {"dataType":"text","outputData":{"text":"Healthy alerts\/hour    : 0.000\n","truncated":false}}
%---
%[output:3dc49121]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay    : 60.0 s\n","truncated":false}}
%---
%[output:99b3e498]
%   data: {"dataType":"text","outputData":{"text":"Healthy alerts\/hour    : 0.000\n","truncated":false}}
%---
%[output:44ed2218]
%   data: {"dataType":"text","outputData":{"text":"\nCapacitor detection    : 85.88 %n","truncated":false}}
%---
%[output:84d6f2eb]
%   data: {"dataType":"text","outputData":{"text":"\nCapacitor detection    : 84.71 %n","truncated":false}}
%---
%[output:608c18a5]
%   data: {"dataType":"text","outputData":{"text":"\nCapacitor detection    : 87.06 %n","truncated":false}}
%---
%[output:2405f03d]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay        : 40.0 s\n","truncated":false}}
%---
%[output:3351d7e2]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay        : 40.0 s\n","truncated":false}}
%---
%[output:14c8b0e9]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay        : 40.0 s\n","truncated":false}}
%---
%[output:66352597]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift detect   : 100.00 %n","truncated":false}}
%---
%[output:29d17210]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift detect   : 98.82 %n","truncated":false}}
%---
%[output:4d347850]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay    : 70.0 s\n","truncated":false}}
%---
%[output:2b3f29dc]
%   data: {"dataType":"text","outputData":{"text":"\n\n============================================================\n","truncated":false}}
%---
%[output:01f21e53]
%   data: {"dataType":"text","outputData":{"text":" FINAL IF V5 - LOCKED FINAL TEST RESULTS\n","truncated":false}}
%---
%[output:896a702f]
%   data: {"dataType":"text","outputData":{"text":"============================================================\n","truncated":false}}
%---
%[output:31847d2e]
%   data: {"dataType":"text","outputData":{"text":"\nLOCKED ARCHITECTURE\n","truncated":false}}
%---
%[output:960955c1]
%   data: {"dataType":"text","outputData":{"text":"Window              : 60 s\n","truncated":false}}
%---
%[output:3d888f56]
%   data: {"dataType":"text","outputData":{"text":"Step                : 10 s\n","truncated":false}}
%---
%[output:0dfa4bd2]
%   data: {"dataType":"text","outputData":{"text":"Trees               : 300\n","truncated":false}}
%---
%[output:8b7968ad]
%   data: {"dataType":"text","outputData":{"text":"Weighting           : targeted\n","truncated":false}}
%---
%[output:28516d3a]
%   data: {"dataType":"text","outputData":{"text":"Persistence         : 3of5\n","truncated":false}}
%---
%[output:7b1625db]
%   data: {"dataType":"text","outputData":{"text":"Threshold rule      : 99th percentile healthy calibration\n","truncated":false}}
%---
%[output:3ab837e0]
%   data: {"dataType":"text","outputData":{"text":"\nFINAL HEALTHY PERFORMANCE\n","truncated":false}}
%---
%[output:2e721504]
%   data: {"dataType":"text","outputData":{"text":"Healthy FAR          : 0.000 +\/- 0.000 %n","truncated":false}}
%---
%[output:31221e56]
%   data: {"dataType":"text","outputData":{"text":"Alert episodes\/hour  : 0.000 +\/- 0.000\n","truncated":false}}
%---
%[output:2c777eaf]
%   data: {"dataType":"text","outputData":{"text":"Threshold             : 0.537186 +\/- 0.005401\n","truncated":false}}
%---
%[output:81b356a3]
%   data: {"dataType":"text","outputData":{"text":"\nFINAL ALL-FAULT RESULTS\n","truncated":false}}
%---
%[output:6e3954a3]
%   data: {"dataType":"text","outputData":{"text":"            <strong>FaultCase<\/strong>            <strong>MeanDetection_percent<\/strong>    <strong>StdDetection_percent<\/strong>    <strong>MeanDetectionDelay_s<\/strong>    <strong>StdDetectionDelay_s<\/strong>    <strong>MeanFaultScore<\/strong>    <strong>MeanMaxFaultScore<\/strong>\n    <strong>_________________________<\/strong>    <strong>_____________________<\/strong>    <strong>____________________<\/strong>    <strong>____________________<\/strong>    <strong>___________________<\/strong>    <strong>______________<\/strong>    <strong>_________________<\/strong>\n\n    {'Power mismatch'       }           9.4118                   5.6422                   220                   160.62              0.50113             0.60752     \n    {'Voltage\/DC-link'      }           87.529                   10.575                    30                        0               0.5608             0.62091     \n    {'Current\/load'         }           8.2353                   4.1595                   220                   159.84              0.49835             0.60655     \n    {'Thermal'              }           3.7647                    2.263                   340                    8.165              0.48727             0.58961     \n    {'Capacitor degradation'}           80.235                   14.704                    40                        0              0.55307             0.60144     \n    {'Sensor drift voltage' }           98.588                   2.5505                    72                   21.679              0.57511             0.62724     \n    {'Open-switch proxy'    }           36.941                   8.3438                    32                   4.4721              0.53077             0.62556     \n\n","truncated":false}}
%---
%[output:61ae8f6e]
%   data: {"dataType":"text","outputData":{"text":"\nFINAL GRADUAL-FAULT PERFORMANCE\n","truncated":false}}
%---
%[output:7bd4d143]
%   data: {"dataType":"text","outputData":{"text":"Capacitor detection       : 80.24 +\/- 14.70 %n","truncated":false}}
%---
%[output:9139ff84]
%   data: {"dataType":"text","outputData":{"text":"Capacitor delay           : 40.0 +\/- 0.0 s\n","truncated":false}}
%---
%[output:318db4f2]
%   data: {"dataType":"text","outputData":{"text":"CapHealth at first alert  : 0.9524 +\/- 0.0000\n","truncated":false}}
%---
%[output:54d5f25e]
%   data: {"dataType":"text","outputData":{"text":"Cap trajectory at alert   : 4.4 +\/- 0.0 %n","truncated":false}}
%---
%[output:07bb5ac1]
%   data: {"dataType":"text","outputData":{"text":"\nVoltage drift detection   : 98.59 +\/- 2.55 %n","truncated":false}}
%---
%[output:629f0887]
%   data: {"dataType":"text","outputData":{"text":"Voltage drift delay       : 72.0 +\/- 21.7 s\n","truncated":false}}
%---
%[output:55963fa3]
%   data: {"dataType":"text","outputData":{"text":"Drift at first alert      : 2.40 +\/- 0.72 V\n","truncated":false}}
%---
%[output:457444a4]
%   data: {"dataType":"text","outputData":{"text":"\nBalanced gradual detect   : 80.24 %n","truncated":false}}
%---
%[output:2cbf1b71]
%   data: {"dataType":"text","outputData":{"text":"Mean gradual detection    : 89.41 %n","truncated":false}}
%---
%[output:8148738c]
%   data: {"dataType":"text","outputData":{"text":"Other-fault mean detect   : 29.18 %n","truncated":false}}
%---
%[output:48f4547c]
%   data: {"dataType":"text","outputData":{"text":"\n====================================\n","truncated":false}}
%---
%[output:1c5c0d41]
%   data: {"dataType":"text","outputData":{"text":"EARLY-WARNING COMPARISON\n","truncated":false}}
%---
%[output:34b9cc8f]
%   data: {"dataType":"text","outputData":{"text":"====================================\n","truncated":false}}
%---
%[output:8aa5dfca]
%   data: {"dataType":"text","outputData":{"text":"Rule-based voltage warning threshold : 20.0 V\n","truncated":false}}
%---
%[output:97052050]
%   data: {"dataType":"text","outputData":{"text":"Mean IF drift at first alert         : 2.40 V\n","truncated":false}}
%---
%[output:0efb37dd]
%   data: {"dataType":"text","outputData":{"text":"Result: IF detected the developing drift before the 20 V deterministic warning threshold.\n","truncated":false}}
%---
%[output:53e897c5]
%   data: {"dataType":"text","outputData":{"text":"\n============================================================\n","truncated":false}}
%---
%[output:21cf7716]
%   data: {"dataType":"text","outputData":{"text":" FINAL IF V5 LOCKED FINAL TEST COMPLETE\n","truncated":false}}
%---
%[output:71487d16]
%   data: {"dataType":"text","outputData":{"text":"============================================================\n","truncated":false}}
%---
%[output:4312186b]
%   data: {"dataType":"text","outputData":{"text":"\nCreated:\n","truncated":false}}
%---
%[output:17e4be76]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_FaultResults.csv\n","truncated":false}}
%---
%[output:11b789f7]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_PerSeedGradualResults.csv\n","truncated":false}}
%---
%[output:74f4f230]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_FinalEvaluation.mat\n","truncated":false}}
%---
%[output:52cd0755]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_Configuration.txt\n","truncated":false}}
%---
%[output:2f535889]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_DetectionRate.png\n","truncated":false}}
%---
%[output:992db42f]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_DetectionDelay.png\n","truncated":false}}
%---
%[output:8f95bc03]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_GradualDetection.png\n","truncated":false}}
%---
%[output:6ccce8c1]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_HealthyFAR.png\n","truncated":false}}
%---
%[output:99909891]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_HealthyScoreTimeline.png\n","truncated":false}}
%---
%[output:2f8b5336]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_CapacitorScoreTimeline.png\n","truncated":false}}
%---
%[output:80f8f4e1]
%   data: {"dataType":"text","outputData":{"text":" FinalIF_V5_LOCKED_VoltageDriftScoreTimeline.png\n","truncated":false}}
%---
%[output:7d95ecc8]
%   data: {"dataType":"text","outputData":{"text":"\n============================================================\n","truncated":false}}
%---
%[output:19641b80]
%   data: {"dataType":"text","outputData":{"text":" IMPORTANT\n","truncated":false}}
%---
%[output:8154f1fd]
%   data: {"dataType":"text","outputData":{"text":"============================================================\n","truncated":false}}
%---
%[output:23220896]
%   data: {"dataType":"text","outputData":{"text":"These are FINAL simulation\/replay test results for the locked architecture.\n","truncated":false}}
%---
%[output:7ad6a8a9]
%   data: {"dataType":"text","outputData":{"text":"Do NOT modify IF hyperparameters based on these final-test results.\n","truncated":false}}
%---
%[output:551336b1]
%   data: {"dataType":"text","outputData":{"text":"Smart SIP field data, when available, will constitute a separate field-calibration\/validation stage.\n","truncated":false}}
%---
