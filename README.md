
# Gyroscope Dynamic RateProviders

These are contracts that implement the `RateProvider` interface and are connected to a chainlink feed but do _not_ automatically reflect the current value of the chainlink feed. Instead, it stores the most recently observed value and everyday operation is like a `ConstantRateProvider` that always returns the same value.

What differentiates them from a `ConstantRateProvider` is that they also have an update method by which the stored value can be updated based on the chainlink feed. This update is not unconditional, though, to avoid an arbitrage loss to LPers.

In the V1 version of the contract, `updateToEdge()` can only be performed when the linked pool is out of range, and then the rate is updated such that the pool is just barely at the respective edge of its price range. In this case, LPers do not incur an arbitrage loss. It is expected that these updates occur rarely.

The rateprovider supports ECLPs in both Balancer V2 and Balancer V3. The Balancer version needs to be indicated in the constructor.

A potential accounting problem occurs if protocol fees are taken on underlying yield while the rateprovider updates. To avoid this, for Balancer V3, the pool must not take protocol fees on underlying yield. For Balancer V2, the rateprovider must be authorized to temporarily set protocol fees to 0.

The update method is permissioned and can only be performed by the respective authorized role. The reason for this is to protect against unknown potential attacks that might be available by performing an update together with some other operation. While we are not aware of any such attack, making the update permissioned serves as a conservative approach here.
