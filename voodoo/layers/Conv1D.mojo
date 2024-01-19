from voodoo import Tensor, shape
from .BaseLayer import BaseLayer


struct Conv1D[
    in_channels: Int,
    kernel_width: Int,
    stride: Int,
    padding: Int,
    use_bias: Bool = False,
    weight_initializer: String = "he_normal",
    bias_initializer: String = "zeros",
    weight_mean: Float32 = 0.0,
    weight_std: Float32 = 0.05,
    bias_mean: Float32 = 0.0,
    bias_std: Float32 = 0.05,
    # TODO: add activation, regularizer, constraint, add 2d strides, add filters
](BaseLayer):
    var W: Tensor
    var bias: Tensor

    fn __init__(
        inout self,
    ) raises:
        self.W = (
            Tensor(shape(in_channels, kernel_width))
            .initialize[weight_initializer, weight_mean, weight_std]()
            .requires_grad()
        )

        @parameter
        if self.use_bias:
            self.bias = (
                Tensor(shape(in_channels, 1, 1))
                .initialize[bias_initializer, bias_mean, bias_std]()
                .requires_grad()
            )
        else:
            self.bias = Tensor(shape(0))

    fn forward(self, x: Tensor) raises -> Tensor[False, False]:
        let res = x.conv_1d(self.W, self.padding, self.stride)

        if self.use_bias:
            return res + self.bias

        return res