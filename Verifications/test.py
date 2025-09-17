import torch

a = torch.tensor((1, 2, 3, 4, 5))
b = torch.cumsum(a, dim=0)

print(b)
