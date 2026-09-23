# Project Summary

## Problem

Inverter faults and gradual degradation can be difficult to detect when operating conditions also change. The project explores a replay-based monitoring approach that compares observed inverter behaviour with a predicted healthy baseline.

## Approach

The MATLAB/Simulink prototype combines:

1. PV and DC-link operating context
2. Three-phase inverter and equivalent motor-pump load
3. Electrical and thermal prediction
4. Residual generation for power, voltage, current and temperature
5. Rule-based diagnostic scoring
6. Controlled electrical, thermal and degradation scenarios
7. Logging for data-driven anomaly-detection development

## Current public files

The current GitHub-ready package contains the main Simulink model, parameter/fault-injection script and a one-fault runner.

The separate Isolation Forest training/evaluation code described in the dissertation has not been supplied in this package yet.

## Validation boundary

The project is simulation-led. Field time-series data and complete proprietary inverter design parameters were unavailable, so a number of model parameters were estimated or based on engineering assumptions. The model should therefore be presented as a research prototype for condition-monitoring development, not as a certified representation of the commercial inverter.
