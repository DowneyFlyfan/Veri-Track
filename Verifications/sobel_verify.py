import torch
import torch.nn.functional as F
import numpy as np
import os
import math
from utils import read_hex_file, write_to_file
import matplotlib.pyplot as plt

np.set_printoptions(threshold=10000, linewidth=10000)


class Tb_machine:
    def __init__(self):
        self.roi_size = 64
        self.in_width = 8
        self.kernel_size = 3
        self.kernel_data_width = 4
        self.adder_tree_input_num = 18
        self.pad_size = (self.kernel_size - 1) // 2
        self.path = "..\\texts\\" if os.name == "nt" else "../texts/"
        self.img_shape = (1, 1, self.roi_size, self.roi_size)
        self.out_width = (
            self.in_width
            + self.kernel_data_width
            + math.ceil(math.log2(self.adder_tree_input_num))
        )

    def data_gen(self, kernel_type="sobel"):
        self.image = torch.randint(
            low=-128,
            high=127,
            size=(1, 1, self.roi_size, self.roi_size),
            dtype=torch.int32,
        )

        if kernel_type == "sobel":
            self.sobel_x = torch.tensor(
                [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=torch.int32
            )
            self.sobel_y = torch.tensor(
                [[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=torch.int32
            )

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

        elif kernel_type == "hessian":
            ...

    def write(self):
        write_to_file(self.image.numpy(), self.path + "input_img.txt", self.in_width)
        write_to_file(
            torch.cat([self.sobel_x, self.sobel_y], dim=0).numpy(),
            self.path + "kernel.txt",
            self.kernel_data_width,
        )
        write_to_file(
            self.expected_output.numpy(),
            self.path + "expected_output.txt",
            self.out_width,
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
                self.path + "expected_output.txt", self.out_width
            ).reshape(self.img_shape)
            verilog_output = read_hex_file(
                self.path + "output_img.txt", self.out_width
            ).reshape(self.img_shape)

            # Display outputs as function plots
            self.display(expected_output.flatten(), verilog_output.flatten())

            # Compare results
            if np.array_equal(expected_output, verilog_output):
                print("\n✅ Verification successful! The outputs match exactly.")
            else:
                diff_indices = np.argwhere(expected_output != verilog_output)
                print(f"Index where difference takes place is {diff_indices}")

                num_diff_elements = np.sum(expected_output != verilog_output)
                print(f"Total number of differing elements: {num_diff_elements}")

        except Exception as e:
            print(f"\nAn error occurred while processing the output file: {e}")

    def forward(self, way, kernel_type="sobel"):
        if way == 1:
            self.data_gen(kernel_type=kernel_type)
            self.write()
        elif way == 2:
            self.verification()
        else:
            raise ValueError("Wrong Value of parameter 'way' ! It should be 1 or 2!!!")


if __name__ == "__main__":
    machine = Tb_machine()
    machine.forward(2)
