import esm
import math
import torch
import torch.nn as nn
import torch.nn.functional as F

from torch.nn.utils.rnn import pack_padded_sequence, pad_packed_sequence

from argparse import Namespace

class ESM1bEmbedding(nn.Module):
    """ ESM1b embedding layer module """

    def __init__(self, embedding_args: dict, embedding_pretrained=None, ft_embed_tokens: bool = False, ft_transformer: bool = False, ft_contact_head: bool = False,
                 ft_embed_positions: bool = False, ft_emb_layer_norm_before: bool = False, ft_emb_layer_norm_after: bool = False, 
                 ft_lm_head: bool = False, max_embedding: int = 1024, offset: int = 200):
        """ Constructor
        Args:
            embedding_args: arguments to embeddings model
            embedding_pretrained: patht to pretrained model
            ft_embed_tokens: finetune embed tokens layer
            ft_transformer: finetune transformer layer
            ft_contact_head: finetune contact head
            ft_embed_positions: finetune embedding positions
            ft_emb_layer_norm_before: finetune embedding layer norm before
            ft_emb_layer_norm_after: finetune embedding layer norm after
            ft_lm_head: finetune lm head layer
            max_embeddings: maximum sequence length for language model
            offset: overlap offset when concatenating sequences above max embedding
        """
        super(ESM1bEmbedding, self).__init__()

        # if given model path then pretrain
        if embedding_pretrained:
            self.model, _ = esm.pretrained.load_model_and_alphabet_local(embedding_pretrained)
        else:
            # configure pre-trained model
            alphabet = esm.Alphabet.from_architecture(embedding_args['arch'])
            model_type = esm.ProteinBertModel

            self.model = model_type(Namespace(**embedding_args), alphabet,)

        self.max_embedding = max_embedding
        self.offset = offset

        # finetuning, freezes all layers by default
        self.finetune = [ft_embed_tokens, ft_transformer, ft_contact_head,
            ft_embed_positions, ft_emb_layer_norm_before, ft_emb_layer_norm_after, ft_lm_head]

        # finetune by freezing unchoosen layers
        for i, child in enumerate(self.model.children()):
            if self.finetune[i] == False:
                for param in child.parameters():
                    param.requires_grad = False

    def forward(self, batch_tokens: torch.tensor, padding_length: int = None) -> torch.tensor:
        """ Convert tokens to embeddings
        Args:
            batch_tokens: tensor with sequence tokens
        """
        batch_residues_original = batch_tokens.shape[1]

        # remove padding
        if padding_length:
            batch_tokens = batch_tokens[:, :padding_length]

        batch_residues = batch_tokens.shape[1]

        embedding = self.model(batch_tokens[:, :self.max_embedding], repr_layers=[33])[
                               "representations"][33]

        batch_iter = math.ceil(batch_residues / (self.max_embedding - self.offset))

        # if size above 1024 then generate embeddings that overlaps with the offset
        if batch_residues >= self.max_embedding:
            # combine by overlaps
            for i in range(1, batch_iter):
                o1 = (self.max_embedding - self.offset) * i
                o2 = o1 + self.max_embedding

                if i == batch_iter - 1:
                    if o2 > batch_residues:
                        embedding = torch.cat([embedding[:, :o1], self.model(
                        batch_tokens[:, o1:batch_residues], repr_layers=[33])["representations"][33]], dim=1)
                    else:
                        embedding = torch.cat([embedding[:, :o2 - self.offset], self.model(
                        batch_tokens[:, o2 - self.offset:batch_residues], repr_layers=[33])["representations"][33]], dim=1)
                else:
                    embedding = torch.cat([embedding[:, :o1], self.model(
                        batch_tokens[:, o1:o2], repr_layers=[33])["representations"][33]], dim=1)


            embedding = torch.nan_to_num(embedding)

        # add padding
        if padding_length:
            embedding = F.pad(embedding, pad=(0, 0, 0, batch_residues_original
                            - padding_length), mode='constant', value=0)

        # cleanup
        del batch_tokens
        torch.cuda.empty_cache()

        return embedding[:, 1:embedding.shape[1]-1, :]


class CNNbLSTM_ESM1b(nn.Module):
    def __init__(self, init_n_channels: int, out_channels: int, cnn_layers: int, kernel_size: tuple, padding: tuple, n_hidden: int, dropout: float, lstm_layers: int, embedding_args: dict, embedding_pretrained: str = None, **kwargs):
        """ Constructor
        Args:
            init_n_channels: size of the incoming feature vector
            out_channels: amount of hidden neurons in the bidirectional lstm
            cnn_layers: amount of cnn layers
            kernel_size: kernel sizes of the cnn layers
            padding: padding of the cnn layers
            n_hidden: amount of hidden neurons
            dropout: amount of dropout
            lstm_layers: amount of bidirectional lstm layers
            language_model: path to language model weights
        """
        super(CNNbLSTM_ESM1b, self).__init__()

        # ESM1b block
        self.embedding = ESM1bEmbedding(embedding_args, embedding_pretrained, **kwargs)

        # CNN blocks
        self.conv = nn.ModuleList()
        for i in range(cnn_layers):
            self.conv.append(nn.Sequential(*[
                nn.Dropout(p=dropout),
                nn.Conv1d(in_channels=init_n_channels, out_channels=out_channels,
                          kernel_size=kernel_size[i], padding=padding[i]),
                nn.ReLU(),
            ]))

        self.batch_norm = nn.BatchNorm1d(init_n_channels + (out_channels * 2))

        # LSTM block
        self.lstm = nn.LSTM(input_size=init_n_channels + (out_channels * 2), hidden_size=n_hidden, batch_first=True,
                            num_layers=lstm_layers, bidirectional=True, dropout=dropout)
        self.lstm_dropout_layer = nn.Dropout(p=dropout)

        # Task block
        self.ss8 = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=8),
        ])
        self.ss3 = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=3),
        ])
        self.disorder = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=2),
        ])
        self.rsa = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=1),
            nn.Sigmoid()
        ])
        self.phi = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=2),
            nn.Tanh()
        ])
        self.psi = nn.Sequential(*[
            nn.Linear(in_features=n_hidden * 2, out_features=2),
            nn.Tanh()
        ])

    def forward(self, x: torch.tensor, mask: torch.tensor) -> list:
        """ Forwarding logic """
        # remove start and end token from length
        max_length = x.size(1) - 2

        x = self.embedding(x, max(mask))
        x = x.permute(0, 2, 1)

        # concatenate channels from residuals and input + batch norm
        r = x
        for layer in self.conv:
            r = torch.cat([r, layer(x)], dim=1)

        x = self.batch_norm(r)

        # calculate double layer bidirectional lstm
        x = x.permute(0, 2, 1)
        x = pack_padded_sequence(x, mask, batch_first=True, enforce_sorted=False)
        x, _ = self.lstm(x)
        x, _ = pad_packed_sequence(x, total_length=max_length, batch_first=True)
        x = self.lstm_dropout_layer(x)

        # hidden neurons to classes
        ss8 = self.ss8(x)
        ss3 = self.ss3(x)
        dis = self.disorder(x)
        rsa = self.rsa(x)
        phi = self.phi(x)
        psi = self.psi(x)

        return [ss8, ss3, dis, rsa, phi, psi]