We start from ixgbe_xmit_pkts_simple, which is the simplest version, there are alternatives for e.g. hardware offloads.
We assume 1 packet (so e.g. no calls to tx4)

```
ixgbe_xmit_pkts_simple
- tx_xmit_pkts
  - ixgbe_tx_free_bufs
  - ixgbe_tx_fill_hw_ring
    - tx1
```
