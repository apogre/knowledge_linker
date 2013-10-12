cimport cython
from libc.stdlib cimport malloc, abort
from libc.string cimport memset

## Return types for shortest_path/bottleneck_path functions

ctypedef struct Path:
    size_t length
    int * vertices
    int found

ctypedef Path * PathPtr

ctypedef struct MetricPath:
    size_t length
    int * vertices
    int found
    double distance

ctypedef MetricPath * MetricPathPtr

## inlines

@cython.profile(False)
@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline int * init_intarray(size_t n, int val) nogil:
    '''
    Allocates memory for holding n int values, and initialize them to val.
    Caller is responsible for free-ing up the memory.
    '''
    cdef:
        void * buf
        int * ret
    buf = malloc(n * sizeof(int))
    if buf == NULL:
        abort()
    memset(buf, val, n * sizeof(int))
    ret = <int *> buf
    return ret

@cython.profile(False)
@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline int _csr_neighbors(int node, int [:] indices, int [:] indptr, int ** ptr) nogil:
    '''
    Extracts the neighbors of given node from the CSR indices and indptr
    structures and copies them on a separate memory location, pointed by ptr.

    Returns the number of neighbors. If the node has no neighbors, no memory is
    allocated.
    '''
    cdef int n, i, I, II
    cdef void * buf
    cdef int * res
    I = indptr[node]
    II = indptr[node + 1]
    n = II - I
    if n > 0:
        buf = malloc(n * sizeof(int))
        if buf == NULL:
            abort()
        res = <int *> buf
        for i in xrange(n):
            res[i] = indices[I + i]
        ptr[0] = res
    return n


