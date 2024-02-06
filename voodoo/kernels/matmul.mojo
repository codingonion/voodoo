from algorithm import vectorize
from math import max, min
from voodoo import Node
from voodoo.utils import recursive_broadcast
from ..constants import PREFETCH_READ, PREFETCH_WRITE, F32_MAX, NELTS

# TODO: Add cleanup for tiling


trait MatMul:
    ...


@register_passable("trivial")
struct MMul(MatMul):
    @staticmethod
    @always_inline("nodebug")
    fn base_case_depth(depth: Int, a: Node, b: Node) -> Bool:
        return depth == max(a.get_num_dims(), b.get_num_dims()) - 2

    @staticmethod
    fn fw(c: Node, a: Node, b: Node):
        recursive_broadcast[Self.kernel_mmul_fw, Self.base_case_depth](c, a, b)

    @staticmethod
    fn bw(c: Node, a: Node, b: Node):
        if not a.get_is_single():
            recursive_broadcast[Self.kernel_mmul_bw_a, Self.base_case_depth](c, a, b)
        if not b.get_is_single():
            recursive_broadcast[Self.kernel_mmul_bw_b, Self.base_case_depth](c, a, b)

    @staticmethod
    fn kernel_mmul_fw(
        c: Node, a: Node, b: Node, a_index: Int, b_index: Int, c_index: Int, depth: Int
    ) -> None:
        let a_num_dims = a.get_num_dims()
        let b_num_dims = b.get_num_dims()

        let M = a.get_shape()[a_num_dims - 2]
        let K = b.get_shape()[b_num_dims - 2]
        let N = c.get_shape()[c.get_num_dims() - 1]

        let offset_a = a_index * M * a.get_shape()[a_num_dims - 1]
        let offset_b = b_index * K * b.get_shape()[b_num_dims - 1]
        let offset_c = c_index * N * N

        let a_data = a.get_data()
        let b_data = b.get_data()
        let c_data = c.get_data()

        DTypePointer.prefetch[PREFETCH_READ](a_data)
        DTypePointer.prefetch[PREFETCH_READ](b_data)
        DTypePointer.prefetch[PREFETCH_READ](c_data)
        DTypePointer.prefetch[PREFETCH_WRITE](c_data)

        alias fw_tile_size = 32

        for m in range(0, M, fw_tile_size):
            let start_offset_c = offset_c + m * N
            let start_offset_a = offset_a + m * K
            for kb in range(0, K, NELTS):
                for k in range(kb, min(kb + NELTS, K)):
                    let b_off = offset_b + k * N

                    @parameter
                    @always_inline("nodebug")
                    fn dot_fw[NELTS: Int](n: Int):
                        let b_data_n = b_data.simd_load[NELTS](b_off + n)

                        @parameter
                        @always_inline("nodebug")
                        fn dot_store(c_off_n: Int, a_off: Int):
                            c_data.simd_store[NELTS](
                                c_off_n,
                                b_data_n.fma(
                                    a_data[a_off + k],
                                    c_data.simd_load[NELTS](c_off_n),
                                ),
                            )

                        @unroll
                        for i in range(fw_tile_size):
                            dot_store(
                                start_offset_c + i * N + n, start_offset_a + i * K
                            )

                    vectorize[NELTS, dot_fw](N)

    @staticmethod
    fn kernel_mmul_bw_a(
        c: Node, a: Node, b: Node, a_index: Int, b_index: Int, c_index: Int, depth: Int
    ) -> None:
        let a_num_dims = a.get_num_dims()
        let b_num_dims = b.get_num_dims()

        let M = a.get_shape()[a_num_dims - 2]
        let K = b.get_shape()[b_num_dims - 2]
        let N = c.get_shape()[c.get_num_dims() - 1]

        let offset_a = a_index * M * a.get_shape()[a_num_dims - 1]
        let offset_b = b_index * K * b.get_shape()[b_num_dims - 1]
        let offset_c = c_index * N * N

        let a_grad = a.get_grad()
        let b_data = b.get_data()
        let c_grad = c.get_grad()

        DTypePointer.prefetch[PREFETCH_READ](a_grad)
        DTypePointer.prefetch[PREFETCH_WRITE](a_grad)
        DTypePointer.prefetch[PREFETCH_READ](b_data)
        DTypePointer.prefetch[PREFETCH_READ](c_grad)

        for m in range(0, M, 2):
            let _offset_c = offset_c + m * N
            let _offset_c_1 = offset_c + (m + 1) * N
            let start_offset_a = offset_a + m * K
            for nb in range(0, N, NELTS):
                for n in range(nb, min(nb + NELTS, N), 2):
                    let c_grad_0 = c_grad[_offset_c + n]
                    let c_grad_1 = c_grad[_offset_c_1 + n]

                    @parameter
                    @always_inline("nodebug")
                    fn dot_bw[NELTS: Int](k: Int):
                        @parameter
                        @always_inline("nodebug")
                        fn dot_store(a_off: Int, b_off: Int, scalar: Float32):
                            a_grad.simd_store[NELTS](
                                a_off,
                                b_data.simd_load[NELTS](b_off).fma(
                                    scalar,
                                    a_grad.simd_load[NELTS](a_off),
                                ),
                            )

                        let start_offset_b = offset_b + k * N

                        dot_store(start_offset_a + k, start_offset_b + n, c_grad_0)
                        dot_store(start_offset_a + K + k, start_offset_b + n, c_grad_1)

                    vectorize[NELTS, dot_bw](K)

    @staticmethod
    fn kernel_mmul_bw_b(
        c: Node, a: Node, b: Node, a_index: Int, b_index: Int, c_index: Int, depth: Int
    ) -> None:
        let a_num_dims = a.get_num_dims()
        let b_num_dims = b.get_num_dims()

        let M = a.get_shape()[a_num_dims - 2]
        let K = b.get_shape()[b_num_dims - 2]
        let N = c.get_shape()[c.get_num_dims() - 1]

        let offset_a = a_index * M * a.get_shape()[a_num_dims - 1]
        let offset_b = b_index * K * b.get_shape()[b_num_dims - 1]
        let offset_c = c_index * N * N

        let a_data = a.get_data()
        let b_grad = b.get_grad()
        let c_grad = c.get_grad()

        DTypePointer.prefetch[PREFETCH_READ](a_data)
        DTypePointer.prefetch[PREFETCH_READ](b_grad)
        DTypePointer.prefetch[PREFETCH_WRITE](b_grad)
        DTypePointer.prefetch[PREFETCH_READ](c_grad)

        if K == 1:
            let _a_off = offset_a
            let _b_off = offset_b

            for m in range(M):
                let a_data = a_data[_a_off + m]
                let _c_off = offset_c + m * N

                @parameter
                @always_inline("nodebug")
                fn dot_bw_single[NELTS: Int](n: Int):
                    let b_off = _b_off + n

                    b.get_grad().simd_store[NELTS](
                        b_off,
                        c_grad.simd_load[NELTS](_c_off + n).fma(
                            a_data,
                            b_grad.simd_load[NELTS](b_off),
                        ),
                    )

                vectorize[NELTS, dot_bw_single](N)
        else:
            for k in range(0, K, 2):
                let _a_off_1 = offset_a + k
                let _a_off_2 = offset_a + k + 1
                let _b_off_1 = offset_b + k * N
                let _b_off_2 = offset_b + (k + 1) * N

                for m in range(M):
                    let a_data_1 = a_data[_a_off_1 + m * K]
                    let a_data_2 = a_data[_a_off_2 + m * K]
                    let _c_off = offset_c + m * N

                    @parameter
                    @always_inline("nodebug")
                    fn dot_bw_inner[NELTS: Int](n: Int):
                        let b_off_1 = _b_off_1 + n
                        let b_off_2 = _b_off_2 + n

                        b.get_grad().simd_store[NELTS](
                            b_off_1,
                            c_grad.simd_load[NELTS](_c_off + n).fma(
                                a_data_1,
                                b_grad.simd_load[NELTS](b_off_1),
                            ),
                        )

                        b.get_grad().simd_store[NELTS](
                            b_off_2,
                            c_grad.simd_load[NELTS](_c_off + n).fma(
                                a_data_2,
                                b_grad.simd_load[NELTS](b_off_2),
                            ),
                        )

                    vectorize[NELTS, dot_bw_inner](N)
