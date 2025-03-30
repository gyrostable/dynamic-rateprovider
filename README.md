
# Gyroscope Dynamic RateProviders

These are contracts that implement the `RateProvider` interface and are connected to a chainlink feed but do _not_ automatically reflect the current value of the chainlink feed. Instead, it stores the most recently observed value and everyday operation is like a `ConstantRateProvider` that always returns the same value.

What differentiates them from a `ConstantRateProvider` is that they also have an update method by which the stored value can be updated based on the chainlink feed. This update is not unconditional, though, to avoid an arbitrage loss to LPers.

In the V1 version of the contract, `updateToEdge()` can only be performed when the linked pool is out of range, and then the rate is updated such that the pool is just barely at the respective edge of its price range. In this case, LPers do not incur an arbitrage loss. It is expected that these updates occur rarely.

The rateprovider supports ECLPs in both Balancer V2 and Balancer V3. The Balancer version needs to be indicated in the constructor.

A potential accounting problem occurs if protocol fees are taken on underlying yield while the rateprovider updates. To avoid this, for Balancer V3, the pool must not take protocol fees on underlying yield. For Balancer V2, the rateprovider must be authorized to temporarily set protocol fees to 0.

The update method is permissioned and can only be performed by the respective authorized role. The reason for this is to protect against unknown potential attacks that might be available by performing an update together with some other operation. While we are not aware of any such attack, making the update permissioned serves as a conservative approach here.

## Dependencies

Dependencies are managed using foundry's system (and therefore are installed automatically on clone) and pnpm. Use `pnpm` to get the latter ones.

Non-standard dependencies:
- `lib/gyro-concentrated-lps-balv2/` - Ad-hoc interface for the ECLP under Balancer v2.

## Operation

The contract uses a two-step initialization procedure to avoid a circular deployment dependency of the `UpdatableRateProvider` vs the pool.

1. When deploying the `UpdatableRateProvider`, the deployer specifies the chainlink feed and the admin.
2. They then specify the `UpdatableRateProvider` as the rate provider of the pool and deploy the pool. The rateprovider will work in this state, but the update function is not available (it would revert).
3. The admin then calls `UpdatableRateProvider.setPool()` to connect the rateprovider to the pool. This can only be done once. The update function is then available.

An `UpdatableRateProvider` *must not* be used for more than one pool. We cannot and do not check this.


