import torch
import torch.nn.functional as F
import numpy as np
import os
import math
import argparse
from utils import read_hex_file, write_to_file
import matplotlib.pyplot as plt

np.set_printoptions(threshold=10000, linewidth=10000)


class TbMachine:
    def __init__(self, roi_size=64, in_width=8, text_path="../texts/"):
        self.roi_size = roi_size
        self.in_width = in_width
        self.path = text_path if os.name == "posix" else text_path.replace("/", "\\")

        if not os.path.exists(self.path):
            os.makedirs(self.path)

        self._define_kernels()

    def _define_kernels(self):
        """Defines the Sobel and Hessian kernels."""
        self.sobel_x = torch.tensor(
            [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=torch.int32
        )
        self.sobel_y = torch.tensor(
            [[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=torch.int32
        )
        self.sobel_xy = torch.cat((self.sobel_x, self.sobel_y), dim=0)
        self.g_xx = torch.tensor(
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
        self.g_xy = torch.tensor(
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
        self.g_yy = torch.tensor(
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

    def _generate_base_data(self, kernel_size):
        """Generates a random image and calculates padding."""
        image = torch.randint(
            low=0,
            high=255,
            size=(1, 1, self.roi_size, self.roi_size),
            dtype=torch.int32,
        )
        pad_size = (kernel_size - 1) // 2
        write_to_file(
            image.numpy(), os.path.join(self.path, "input_img.txt"), self.in_width
        )
        return image, pad_size

    def generate_sobel_data(self):
        """Generates test data for the Sobel operator."""
        kernel_data_width = 3
        kernel_size = 3
        out_width = 12

        image, pad_size = self._generate_base_data(kernel_size)

        expected_output = F.conv2d(
            image, self.sobel_xy.view(2, 1, kernel_size, kernel_size), padding=pad_size
        )
        expected_output = torch.sum(torch.abs(expected_output), dim=1, keepdim=True)

        print(f"max value of sobel conv output is {expected_output.max()}, ")

        expected_output = expected_output / expected_output.max()
        expected_output[0, 0, -6:, :] = 0
        expected_output[0, 0, :6, :] = 0
        expected_output[0, 0, :, -6:] = 0
        expected_output[0, 0, :, :6] = 0

        kernels = torch.cat([self.sobel_x, self.sobel_y], dim=0).numpy()

        write_to_file(
            kernels,
            os.path.join(self.path, "sobel_kernel.txt"),
            kernel_data_width,
            fractional_bits=0,
            mode="bin",
        )
        write_to_file(
            expected_output.numpy(),
            os.path.join(self.path, "expected_output.txt"),
            out_width,
            fractional_bits=11,  # 第一位是符号位
        )

    def generate_hessian_data(self):
        """Generates test data for the Hessian operator."""
        kernel_data_width = 12
        kernel_size = 5
        out_width = 20

        image, pad_size = self._generate_base_data(kernel_size)

        kernels_cat = torch.cat((self.g_xx, self.g_yy, self.g_xy), dim=0)
        expected_output = F.conv2d(
            input=image.float(),
            weight=kernels_cat.unsqueeze(1),
            groups=1,
            padding=pad_size,
        )

        write_to_file(
            kernels_cat,
            os.path.join(self.path, "sobel_kernel.txt"),
            kernel_data_width,
            fractional_bits=11,
        )
        write_to_file(
            expected_output.numpy(),
            os.path.join(self.path, "expected_output.txt"),
            out_width,
            fractional_bits=11,  # FIX:等会改一下
        )

    def _plot_results(self, expected_flat, verilog_flat):
        """Displays the expected and Verilog outputs as plots."""
        plt.figure(figsize=(14, 6))
        plt.subplot(1, 2, 1)
        plt.plot(expected_flat, label="Expected Output")
        plt.title("Expected Output")
        plt.xlabel("Pixel Index")
        plt.ylabel("Pixel Value")
        plt.legend()
        plt.grid(True)

        plt.subplot(1, 2, 2)
        plt.plot(verilog_flat, label="Verilog Output", color="orange")
        plt.title("Verilog Output")
        plt.xlabel("Pixel Index")
        plt.ylabel("Pixel Value")
        plt.legend()
        plt.grid(True)

        plt.tight_layout()
        plt.show()

    def verify_output(self, kernel_type):
        """Verifies the Verilog output against the expected output."""
        if kernel_type == "sobel":
            kernel_data_width = 4
            kernel_frac_width = 0
            img_shape = (1, 1, self.roi_size, self.roi_size)
        elif kernel_type == "hessian":
            kernel_data_width = 16
            kernel_frac_width = 15
            img_shape = (1, 3, self.roi_size, self.roi_size)
        else:
            raise ValueError("Invalid kernel type for verification.")

        out_width = self.in_width + kernel_data_width

        expected_path = os.path.join(self.path, "expected_output.txt")
        verilog_path = os.path.join(self.path, "output_img.txt")

        if not os.path.exists(expected_path) or not os.path.exists(verilog_path):
            print(
                f"Error: Missing output files. Ensure '{expected_path}' and '{verilog_path}' exist."
            )
            return

        try:
            expected_output = read_hex_file(
                expected_path, out_width, fractional_bits=kernel_frac_width
            ).reshape(img_shape)
            verilog_output = read_hex_file(verilog_path, out_width).reshape(img_shape)

            self._plot_results(expected_output.flatten(), verilog_output.flatten())

            if np.allclose(expected_output, verilog_output, atol=1e-2):
                print("\n✅ Verification successful! The outputs match.")
            else:
                print("\n❌ Verification failed! Outputs do not match.")
                diff_indices = np.argwhere(
                    np.abs(expected_output - verilog_output) > 1e-2
                )
                print(f"Found {len(diff_indices)} differing elements.")
                # Optionally print some differing values
                for i in range(min(5, len(diff_indices))):
                    idx = tuple(diff_indices[i])
                    print(
                        f"  - Index {idx}: Expected={expected_output[idx]:.4f}, Got={verilog_output[idx]:.4f}"
                    )

        except Exception as e:
            print(f"\nAn error occurred during verification: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Testbench Generator and Verifier for Convolution Operations"
    )
    parser.add_argument(
        "action",
        choices=["generate", "verify"],
        help="Action to perform: 'generate' data or 'verify' output.",
    )
    parser.add_argument(
        "kernel_type", choices=["sobel", "hessian"], help="Type of kernel to use."
    )
    parser.add_argument(
        "--roi_size", type=int, default=64, help="Region of Interest size."
    )
    parser.add_argument("--in_width", type=int, default=8, help="Input data width.")
    parser.add_argument(
        "--path",
        type=str,
        default="../texts/" if os.name == "posix" else "..\\texts\\",
        help="Path to text files.",
    )

    args = parser.parse_args()

    machine = TbMachine(
        roi_size=args.roi_size, in_width=args.in_width, text_path=args.path
    )

    if args.action == "generate":
        if args.kernel_type == "sobel":
            machine.generate_sobel_data()
        elif args.kernel_type == "hessian":
            machine.generate_hessian_data()
        print("Input, expected output and kernel are generated!")
    elif args.action == "verify":
        machine.verify_output(args.kernel_type)


if __name__ == "__main__":
    main()
