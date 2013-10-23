# cython: profile=False

import numpy as np
import scipy.sparse as sp

# cimports
cimport numpy as cnp
cimport cython
from libc.stdlib cimport malloc, free, calloc
from libc.stdio cimport printf
from .heap cimport FastUpdateBinaryHeap
from .cmaxmin cimport _csr_neighbors, init_intarray, MetricPathPtr, MetricPath

cpdef object bottlenecknodefull(object G, int retpath=0):
    rows = []
    paths = []
    N = G.shape[0]
    for s in xrange(N):
        row, p = bottlenecknode(G, s, retpath=retpath)
        rows.append(row)
        paths.append(p)
    return np.asarray(rows), paths

cpdef object bottlenecknode(object G, int s, object targets=None, int retpath=0):
    '''
    Return the bottleneck capacity and paths from node s. If no targets are
    specified, will return the capacities for all possible targets in the graph.
    '''
    N = G.shape[0]
    if targets is None:
        targets = xrange(N)
    capacities = []
    paths = []
    for t in targets:
        c, p = bottlenecknodest(G, s, t, retpath=retpath)
        paths.append(p)
        capacities.append(c)
    capacities = np.asarray(capacities)
    return capacities, paths

@cython.boundscheck(False)
@cython.wraparound(False)
cpdef object bottlenecknodest(object A, int source, int target, int retpath = 0):
    '''
    Computes the intermediate bottleneck capacity (or distance) from `source`
    to `target` on the undirected graph represented by adjacency matrix `A`.
    Return the capacity and optionally the associated bottleneck node path.

    An intermediate bottleneck node path corresponds to the path that maximizes
    the minimum capacity on its intermediate nodes, that is, excluding the final
    node. If source and target are direct neighbors, or the same node, the
    capacity is by definition 1.0.

    Parameters
    ----------
    A : array_like
        NxN weighted adjancency matrix, will be converted to compressed sparse
        row format. Weights are double floats.

    source : int
        The source node.

    target : int 
        The target node.

    retpath : int
        optional; if True, compute and return the path, or an empty array for
        disconnected source-target pairs. Default is no path returned.

    Returns
    -------
    cap : (N,) double float
        the intermediate bottleneck capacity from source to target in
        the graph, or -1 if the two nodes are disconnected. 

    path : ndarray of ints
        optional; the associated path of nodes (excluding the source).
    '''
    A = sp.csr_matrix(A)
    cdef:
        int [:] A_indptr = A.indptr
        int [:] A_indices = A.indices
        double [:] A_data = A.data
        int N = A.shape[0]
        int i
        MetricPath path
        double ret_cap
        object ret_path = None
    path = _bottlenecknodest(N, A_indptr, A_indices, A_data, source, target, retpath)
    ret_cap = path.distance
    if retpath:
        if path.found and path.vertices != NULL:
            ret_path = np.asarray((<int [:path.length]>path.vertices).copy())
            free(<void *>path.vertices)
        else:
            ret_path = np.empty(0, dtype=np.int)
    return ret_cap, ret_path

# we push the negative of the similarities to fake a max heap
@cython.boundscheck(False)
@cython.wraparound(False)
cdef MetricPath _bottlenecknodest(
        int N,
        int [:] indptr,
        int[:] indices,
        double [:] data,
        int source,
        int target,
        int retpath):
    cdef:
        FastUpdateBinaryHeap Q = FastUpdateBinaryHeap(N, N)
        int * P = init_intarray(N, -1)
        int * certain = init_intarray(N, 0)
        int * tmp = init_intarray(N, -1) # stores path in reverse order
        # the bottleneck capacities
        double * caps = <double *> malloc(N * sizeof(double))
        int * neighbors = NULL
        int node, i, hopscnt
        int N_neigh
        double cap, w, neigh_cap, path_cap
        MetricPathPtr paths = <MetricPathPtr> malloc(N * sizeof(MetricPath))
        MetricPath path
    N_neigh = _csr_neighbors(source, indices, indptr, &neighbors)
    cdef int is_neighbor = 0
    for i in xrange(N_neigh):
        if target == neighbors[i]:
            is_neighbor = 1
            break
    if source == target or is_neighbor:
        caps[target] = 1.0
        P[target] = source
    else:
        # populate the queue
        for node in xrange(N):
            if node == source:
                sim = 1.0
            else:
                sim = 0.0
            caps[node] = sim
            Q.push_fast(- sim, node)
        while Q.count:
            cap = - Q.pop_fast()
            node = Q._popped_ref
            certain[node] = True
            caps[node] = cap
            if node == target:
                break
            N_neigh = _csr_neighbors(node, indices, indptr, &neighbors)
            for i in xrange(N_neigh):
                neighbor = neighbors[i]
                if not certain[neighbor]:
                    neigh_cap = - Q.value_of_fast(neighbor)
                    w = data[indptr[node] + i] # i.e. A[node, neigh_node]
                    if neighbor != target:
                        path_cap = min(w, cap)
                    else:
                        path_cap = cap
                    if path_cap > neigh_cap:
                        Q.push_if_lower_fast(- path_cap, neighbor)
                        P[neighbor] = node
            free(<void *> neighbors)
            neighbors = NULL
    path.vertices = NULL
    if P[target] == -1:
        path.found = 0
        path.distance = -1
        path.length = -1
    else:
        path.found = 1
        path.distance = caps[target]
        if retpath and source != target and not is_neighbor:
            hopscnt = 0
            i = target
            while i != source:
                tmp[hopscnt] = i
                hopscnt += 1
                i = P[i]
            path.length = hopscnt + 1
            path.vertices = <int *>calloc(hopscnt + 1, sizeof(int))
            path.vertices[0] = source
            for i in xrange(hopscnt):
                path.vertices[hopscnt - i] = tmp[i]
        elif source == target: # retpath is True
            path.length = 0
    free(<void *>tmp)
    free(<void *>P)
    free(<void *>certain)
    free(<void *>caps)
    return path