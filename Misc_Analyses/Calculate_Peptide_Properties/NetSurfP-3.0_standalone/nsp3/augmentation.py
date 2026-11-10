import esm
import torch
import torchvision.transforms as transforms

from nsp3.config import RESIDUE_TRANSLATION

class SparseToString(object):
    """ Converts a residue sparse encoding back to sequence """

    def __init__(self):
        self.translate = RESIDUE_TRANSLATION

    def __call__(self, x):
        # get sparse positions
        x = (torch.argmax(x[:, :, :20], axis=2) + 1) * torch.amax(x[:, :, :20], axis=2)

        sequences = []

        # decode sparse encoding to residue sequence
        batches = x.shape[0]
        for i in range(batches):
            sequence = "".join(
                map(lambda r: self.translate[r.item()], x[i]))
            sequences.append(("protein_" + str(i), sequence))

        return sequences


class ESM1bTokenize(object):
    """ Tokenizes a sequence for ESM1b model input """

    def __init__(self):
        alphabet = esm.Alphabet.from_architecture("ESM-1b")
        self.batch_converter = alphabet.get_batch_converter()

    def __call__(self, x):
        batch_labels, batch_strs, batch_tokens = self.batch_converter(x)
        return batch_tokens

def sparse_token():
    return transforms.Compose([SparseToString(), ESM1bTokenize()])


def string_token():
    return transforms.Compose([ESM1bTokenize()])