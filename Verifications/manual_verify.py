import torch
import numpy as np
from Verifications.utils import to_hex

# This is the ground truth from verify.py
g_xx = torch.tensor(
    [
        [
            [0.0087, 0.0000, -0.0215, 0.0000, 0.0087],
            [0.0392, 0.0000, -0.0965, 0.0000, 0.0392],
            [0.0646, 0.0000, -0.1592, 0.0000, 0.0646],
            [0.0392, 0.0000, -0.0965, 0.0000, 0.0392],
            [0.0087, 0.0000, -0.0215, 0.0000, 0.0087],
        ]
    ],
    dtype=torch.float32,
)
g_xy = torch.tensor(
    [
        [
            [0.0117, 0.0261, -0.0000, -0.0261, -0.0117],
            [0.0261, 0.0585, -0.0000, -0.0585, -0.0261],
            [-0.0000, -0.0000, 0.0000, 0.0000, 0.0000],
            [-0.0261, -0.0585, 0.0000, 0.0585, 0.0261],
            [-0.0117, -0.0261, 0.0000, 0.0261, 0.0117],
        ]
    ],
    dtype=torch.float32,
)
g_yy = torch.tensor(
    [
        [
            [0.0087, 0.0392, 0.0646, 0.0392, 0.0087],
            [0.0000, 0.0000, 0.0000, 0.0000, 0.0000],
            [-0.0215, -0.0965, -0.1592, -0.0965, -0.0215],
            [0.0000, 0.0000, 0.0000, 0.0000, 0.0000],
            [0.0087, 0.0392, 0.0646, 0.0392, 0.0087],
        ]
    ],
    dtype=torch.float32,
)

width = 16
fractional_bits = 15
scale_factor = 2**fractional_bits

# Manually convert to hex
hessian_kernels_manual_hex = []
for tensor in [g_xx, g_yy, g_xy]:
    for val in tensor.flatten():
        scaled_val = int(round(val.item() * scale_factor))
        hex_val = to_hex(scaled_val, width)
        hessian_kernels_manual_hex.append(hex_val)

# Read from file
with open("texts/hessian_kernel.txt", "r") as f:
    hessian_kernels_from_file = [line.strip() for line in f.readlines()]

# Compare
if hessian_kernels_manual_hex == hessian_kernels_from_file:
    print("✅ Hessian kernel verification successful!")
else:
    print("❌ Hessian kernel verification failed!")
    # Find and print differences
    for i, (manual, from_file) in enumerate(zip(hessian_kernels_manual_hex, hessian_kernels_from_file)):
        if manual != from_file:
            print(f"Mismatch at index {i}: Manual={manual}, File={from_file}")
