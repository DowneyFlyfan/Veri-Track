import numpy as np
import math


def to_hex(val, width):
    """Converts a signed integer to a two's complement hex string."""
    # Clamp the value to the representable range
    min_val = -(1 << (width - 1))
    max_val = (1 << (width - 1)) - 1
    val = max(min_val, min(val, max_val))

    # Correctly compute the two's complement representation for all numbers
    if val < 0:
        val += (1 << width)

    hex_chars = math.ceil(width / 4)
    return format(val, f"0{hex_chars}x")


def write_to_file(data, filename, width):
    """Writes numpy data to a file in hex format."""
    with open(filename, "w") as f:
        for val in data.flatten():
            f.write(f"{to_hex(int(val), width)}\n")


def read_hex_file(filename, width):
    """Reads a hex file and converts to signed integers."""
    with open(filename, "r") as f:
        hex_values = [line.strip() for line in f.readlines()]

    int_values = []
    for hex_val in hex_values:
        val = int(hex_val, 16)
        if (val >> (width - 1)) & 1:  # Check sign bit
            val -= 1 << width  # Convert to negative
        int_values.append(val)
    return np.array(int_values)
