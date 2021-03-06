#include <string.h>

#include "utils.h"
#include "params.h"
#include "hashx4.h"
#include "address.h"

/**
 * For a given leaf index, computes the authentication path and the resulting
 * root node using Merkle's TreeHash algorithm.
 * Expects the layer and tree parts of the tree_addr to be set, as well as the
 * tree type (i.e. SPX_ADDR_TYPE_HASHTREE or SPX_ADDR_TYPE_FORSTREE).
 * Applies the offset idx_offset to indices before building addresses, so that
 * it is possible to continue counting indices across trees.
 */
void treehashx4(unsigned char *rootx4, unsigned char *auth_pathx4,
                const unsigned char *sk_seed, const unsigned char *pub_seed,
                uint32_t leaf_idx[4], uint32_t idx_offset[4],
                uint32_t tree_height,
                void (*gen_leafx4)(
                   unsigned char* /* leaf0 */,
                   unsigned char* /* leaf1 */,
                   unsigned char* /* leaf2 */,
                   unsigned char* /* leaf3 */,
                   const unsigned char* /* sk_seed */,
                   const unsigned char* /* pub_seed */,
                   uint32_t /* addr_idx0 */,
                   uint32_t /* addr_idx1 */,
                   uint32_t /* addr_idx2 */,
                   uint32_t /* addr_idx3 */,
                   const uint32_t[8] /* tree_addr */),
                uint32_t tree_addrx4[4*8])
{
    unsigned char stackx4[4*(tree_height + 1)*SPX_N];
    unsigned int heights[tree_height + 1];
    unsigned int offset = 0;
    uint32_t idx;
    uint32_t tree_idx;
    unsigned int j;

    for (idx = 0; idx < (uint32_t)(1 << tree_height); idx++) {
        /* Add the next leaf node to the stack. */
        gen_leafx4(stackx4 + 0*(tree_height + 1)*SPX_N + offset*SPX_N,
                   stackx4 + 1*(tree_height + 1)*SPX_N + offset*SPX_N,
                   stackx4 + 2*(tree_height + 1)*SPX_N + offset*SPX_N,
                   stackx4 + 3*(tree_height + 1)*SPX_N + offset*SPX_N,
                   sk_seed, pub_seed,
                   idx + idx_offset[0],
                   idx + idx_offset[1],
                   idx + idx_offset[2],
                   idx + idx_offset[3],
                   tree_addrx4);
        offset++;
        heights[offset - 1] = 0;

        /* If this is a node we need for the auth path.. */
        for (j = 0; j < 4; j++) {
            if ((leaf_idx[j] ^ 0x1) == idx) {
                memcpy(auth_pathx4 + j*tree_height*SPX_N,
                       stackx4 + j*(tree_height + 1)*SPX_N + (offset - 1)*SPX_N, SPX_N);
            }
        }

        /* While the top-most nodes are of equal height.. */
        while (offset >= 2 && heights[offset - 1] == heights[offset - 2]) {
            /* Compute index of the new node, in the next layer. */
            tree_idx = (idx >> (heights[offset - 1] + 1));

            /* Set the address of the node we're creating. */
            for (j = 0; j < 4; j++) {
                set_tree_height(tree_addrx4 + j*8, heights[offset - 1] + 1);
                set_tree_index(tree_addrx4 + j*8,
                               tree_idx + (idx_offset[j] >> (heights[offset-1] + 1)));
            }
            /* Hash the top-most nodes from the stack together. */
            thashx4(stackx4 + 0*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 1*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 2*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 3*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 0*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 1*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 2*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N,
                    stackx4 + 3*(tree_height + 1)*SPX_N + (offset - 2)*SPX_N, 2, pub_seed, tree_addrx4);
            offset--;
            /* Note that the top-most node is now one layer higher. */
            heights[offset - 1]++;

            /* If this is a node we need for the auth path.. */
            for (j = 0; j < 4; j++) {
                if (((leaf_idx[j] >> heights[offset - 1]) ^ 0x1) == tree_idx) {
                    memcpy(auth_pathx4 + j*tree_height*SPX_N + heights[offset - 1]*SPX_N,
                           stackx4 + j*(tree_height + 1)*SPX_N + (offset - 1)*SPX_N, SPX_N);
                }
            }
        }
    }

    for (j = 0; j < 4; j++) {
        memcpy(rootx4 + j*SPX_N, stackx4 + j*(tree_height + 1)*SPX_N, SPX_N);
    }
}
