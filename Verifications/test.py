import torch

a = torch.tensor(112, dtype=torch.int8)
b = torch.tensor(113, dtype=torch.int8)
c = a + b

print(f"c is {c}, data type is {c.dtype}")
