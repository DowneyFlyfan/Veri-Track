import numpy as np
import math


def to_hex(val, width):
    """Converts a signed integer to a hex string of a given bit width."""
    num_hex_chars = (width + 3) // 4
    if val < 0:
        val = (1 << width) + val
    return format(val, f"0{num_hex_chars}x")


def to_bin(val, width):
    """Converts a signed integer to a binary string of a given bit width."""
    if val < 0:
        val = (1 << width) + val
    return format(val, f"0{width}b")


def write_to_file(data, filename, width, fractional_bits=0, mode="hex"):
    """Writes numpy data to a file in hex format."""
    with open(filename, "w") as f:
        flattened_data = data.flatten()

        if np.issubdtype(flattened_data.dtype, np.floating):
            if fractional_bits > 0:
                scale_factor = 2**fractional_bits
                scaled_data = [int(round(val * scale_factor)) for val in flattened_data]
            else:
                scaled_data = [int(round(val)) for val in flattened_data]
        else:
            scaled_data = [int(val) for val in flattened_data]

        if mode == "hex":
            for int_val in scaled_data:
                f.write(f"{to_hex(int_val, width)}\n")
        elif mode == "bin":
            for int_val in scaled_data:
                f.write(f"{to_bin(int_val, width)}\n")


def read_hex_file(filename, width, fractional_bits=0):
    """Reads a hex file and converts to signed integers or floats."""
    with open(filename, "r") as f:
        hex_values = [line.strip() for line in f.readlines()]

    values = []
    for hex_val in hex_values:
        val = int(hex_val, 16)
        if (val >> (width - 1)) & 1:  # Check sign bit
            val -= 1 << width  # Convert to negative

        if fractional_bits > 0:
            scale_factor = float(1 << fractional_bits)
            values.append(float(val) / scale_factor)
        else:
            values.append(val)
    return np.array(values)
