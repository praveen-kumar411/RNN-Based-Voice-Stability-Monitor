# RNN-Based-Voice-Stability-Monitor
A low-power Verilog chip that checks call quality in real time. Every 10–20 ms, a GRU neural network scores 8 voice features (jitter, packet loss, noise) from 0 to 1. A running average raises an alert when quality drops. Verified bit-exact against a Python model; 90 nm, 0.31 mm², ~1.8 mW, 132 µs per frame.
