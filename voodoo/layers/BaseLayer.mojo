from voodoo import Tensor


trait BaseLayer:
    
    @always_inline
    fn __init__(inout self) raises:
        ...
    
    @always_inline
    fn forward(self, x: Tensor) raises -> Tensor[False, False]:
        ...
