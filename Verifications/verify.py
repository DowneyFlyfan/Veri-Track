import torch
import torch.nn.functional as F
import numpy as np
import os
import math
from utils import read_hex_file, write_to_file
import matplotlib.pyplot as plt

np.set_printoptions(threshold=10000, linewidth=10000)


class Tb_machine:
    def __init__(self, kernel_type="sobel"):
        self.roi_size = 64
        self.in_width = 8
        self.kernel_data_width = 16
        self.kernel_frac_width = 15
        self.adder_tree_input_num = 18

        self.path = "../texts/" if os.name == "posix" else "..\\texts\\"

        self.out_width = (
            self.in_width
            + self.kernel_data_width
            + math.ceil(math.log2(self.adder_tree_input_num))
        )
        self.out_frac_width = self.kernel_frac_width

        # Sobel kernels
        self.sobel_x = torch.tensor(
            [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=torch.int32
        )
        self.sobel_y = torch.tensor(
            [[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=torch.int32
        )

        # Hessian kernels
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

        if kernel_type == "sobel":
            self.img_shape = (1, 1, self.roi_size, self.roi_size)
        elif kernel_type == "hessian":
            self.img_shape = (1, 3, self.roi_size, self.roi_size)
        self.kernel_type = kernel_type

    def sobel_data_gen(self):

        self.image = torch.randint(
            low=-128,
            high=127,
            size=(1, 1, self.roi_size, self.roi_size),
            dtype=torch.int32,
        )
        self.kernel_size = 3
        self.pad_size = (self.kernel_size - 1) // 2

        # Conv
        conv_x = F.conv2d(
            self.image,
            self.sobel_x.view(1, 1, self.kernel_size, self.kernel_size),
            padding=self.pad_size,
        )
        conv_y = F.conv2d(
            self.image,
            self.sobel_y.view(1, 1, self.kernel_size, self.kernel_size),
            padding=self.pad_size,
        )
        self.expected_output = conv_x + conv_y

        write_to_file(
            torch.cat([self.sobel_x, self.sobel_y], dim=0).numpy(),
            self.path + "sobel_kernel.txt",
            self.kernel_data_width,
        )
        self.write_common_files()

    def hessian_data_gen(self):

        self.image = torch.randint(
            low=-128,
            high=127,
            size=(1, 1, self.roi_size, self.roi_size),
            dtype=torch.int32,
        )
        self.kernel_size = 5
        self.pad_size = (self.kernel_size - 1) // 2

        self.expected_output = F.conv2d(
            input=self.image.float(),
            weight=torch.cat((self.g_xx, self.g_yy, self.g_xy), dim=0).unsqueeze(1),
            groups=1,
            padding=self.pad_size,
        )

        write_to_file(
            torch.cat([self.g_xx, self.g_yy, self.g_xy], dim=0).numpy(),
            self.path + "hessian_kernel.txt",
            self.kernel_data_width,
            self.kernel_frac_width,
        )
        self.write_common_files()

    def write_common_files(self):
        write_to_file(self.image.numpy(), self.path + "input_img.txt", self.in_width)
        write_to_file(
            self.expected_output.numpy(),
            self.path + "expected_output.txt",
            self.out_width,
            self.out_frac_width,
        )
        print("input_img.txt, kernel.txt, and expected_output generated.")

    def display(self, expected_flat, verilog_flat):
        # Create a single figure with two subplots
        plt.figure(figsize=(14, 6))

        # Subplot for Expected Output
        plt.subplot(1, 2, 1)  # 1 row, 2 columns, first plot
        plt.plot(expected_flat, label="Expected Output")
        plt.title("Expected Output: Pixel Value vs. Index")
        plt.xlabel("Pixel Index")
        plt.ylabel("Pixel Value")
        plt.legend()
        plt.grid(True)

        # Subplot for Verilog Output
        plt.subplot(1, 2, 2)  # 1 row, 2 columns, second plot
        plt.plot(verilog_flat, label="Verilog Output", color="orange")
        plt.title("Verilog Output: Pixel Value vs. Index")
        plt.xlabel("Pixel Index")
        plt.ylabel("Pixel Value")
        plt.legend()
        plt.grid(True)

        plt.tight_layout()  # Adjust layout to prevent overlapping titles/labels
        plt.show()

    def verification(self):
        # Check the result
        if not os.path.exists(self.path + "expected_output.txt"):
            print("\n'expected_output.txt' not found.")
            return
        if not os.path.exists(self.path + "output_img.txt"):
            print("\n'output_img.txt' not found.")
            return

        try:
            expected_output = read_hex_file(
                self.path + "expected_output.txt", self.out_width, self.out_frac_width
            ).reshape(self.img_shape)
            verilog_output = read_hex_file(
                self.path + "output_img.txt", self.out_width, self.out_frac_width
            ).reshape(self.img_shape)

            # Display outputs as function plots
            self.display(expected_output.flatten(), verilog_output.flatten())

            # Compare results
            if np.allclose(expected_output, verilog_output, atol=1e-2):
                print("\n✅ Verification successful! The outputs match exactly.")
            else:
                diff_indices = np.argwhere(expected_output != verilog_output)
                print(f"Index where difference takes place is {diff_indices}")

                num_diff_elements = np.sum(expected_output != verilog_output)
                print(f"Total number of differing elements: {num_diff_elements}")

        except Exception as e:
            print(f"\nAn error occurred while processing the output file: {e}")

    def forward(self, way):
        if way == 1:
            if self.kernel_type == "sobel":
                self.sobel_data_gen()
            elif self.kernel_type == "hessian":
                self.hessian_data_gen()
        elif way == 2:
            self.verification()
        else:
            raise ValueError("Wrong Value of parameter 'way' ! It should be 1 or 2!!!")


if __name__ == "__main__":
    machine = Tb_machine(kernel_type="hessian")
    machine.forward(way=2)
