// Network publication delta. Floating-point noise below this threshold is treated as unchanged.
ACME_net_epsilon = 0.005;

// B203: the full Extended circulation HashMap is large (~90 fields). Owner-local simulation remains 4 Hz,
// while remote/JIP snapshots are capped to this cadence unless a coarse critical-state signature changes.
ACME_circ_stateNetInterval = 2.0;
