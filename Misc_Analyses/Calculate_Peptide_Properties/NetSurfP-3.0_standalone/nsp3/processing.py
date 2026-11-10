import torch
import numpy as np
import torch.nn.functional as F

def arctan_dihedral(sin: torch.tensor, cos: torch.tensor) -> torch.tensor:
    """ Conversion of arctan to dihedral angles  """
    result = torch.where(cos >= 0, torch.arctan(sin / cos),
                         torch.arctan(sin / cos) + np.pi)
    result = torch.where((sin <= 0) & (cos <= 0), result - np.pi * 2, result)

    return result * 180 / np.pi

class PredictNSP3():
    def __init__(self, model, transform, device):
        self.model = model
        self.transform = transform()
        self.device = device

        self.model = self.model.to(device)

    def inference(self, x, mask):
        """ Transforming and forwarding data to model """

        x = self.transform(x)
        x = self.model(x.to(self.device), mask)
        return x

    def postprocessing(self, x):
        """ Processing of the ouput from the model """

        # convert phi and psi radians to angles
        for i in range(x[0].shape[0]):
            x[0][i] = F.softmax(x[0][i], dim=1)
            x[1][i] = F.softmax(x[1][i], dim=1)
            x[2][i] = F.softmax(x[2][i], dim=1)
            
            x[4][i, :, 0] = arctan_dihedral(x[4][i][:, 0], x[4][i][:, 1])
            x[5][i, :, 0] = arctan_dihedral(x[5][i][:, 0], x[5][i][:, 1])

        x[4] = x[4][:, :, 0].unsqueeze(2)
        x[5] = x[5][:, :, 0].unsqueeze(2)

        return x

    def __call__(self, fasta):
        """ Prediction call logic """
        mask = [len(x[1]) for x in fasta]
        x = self.inference(fasta, mask)
        x = self.postprocessing(x)

        identifier = [element[0] for element in fasta]
        sequence = [element[1] for element in fasta]
        prediction = [x[i].detach().cpu().numpy() for i in range(len(x))]

        return identifier, sequence, prediction