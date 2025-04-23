
# Gyroscope Dynamic RateProviders

These are contracts that implement the `RateProvider` interface and are connected to a price feed but do _not_ automatically reflect the current value of the feed. Instead, everyday operation is like a `ConstantRateProvider` that always returns the same stored value. What differentiates these rateproviders from a `ConstantRateProvider` is that they also have an update method by which the stored value can be updated based on the feed. This update is conditional, though, to avoid an arbitrage loss / MEV exposure to LPers.

The `feed` rateprovider is often a `ChainlinkRateProvider` that pulls prices from chainlink, but it could also be a contract that implements some transformation of oracle feeds (e.g., the quotient of two oracle feeds to get a relative price). In any case, it is assumed that the `feed` returns a live market price.

In the V1 version of the contract (which is currently implemented here), the stored value can only be updated when the linked pool is out of range (via `updateToEdge()`), and then the rate is updated such that the pool is just at the respective edge of its price range. In this case, LPers do not incur an arbitrage loss. It is expected that these updates occur rarely.

To be able to know the price range of the pool, the rateprovider must know the interface of the pool. Currently, the following pools are supported: 2CLP and ECLP on both Balancer V2 and V3 and 3CLP on Balancer V2. (The 3CLP is not yet implemented on Balancer V3)

This repository contains a version of the updatable rateprovider for Balancer V2 and another version for Balancer V3.

A potential accounting problem occurs if protocol fees are taken on underlying yield while the rateprovider updates because this accounting cannot differentiate yield from updates to the rate. To avoid this, for Balancer V3, the pool must not take protocol fees on underlying yield, at least for the asset connected to the updatable rateprovider. For Balancer V2, the rateprovider must be authorized to temporarily set protocol fees to 0.

The update method is permissioned and can only be performed by the respective authorized role. This is a conservative measure to protect against potential unknown attacks that might be available by performing an update together with some other manipulation. While we are not aware of any such attack, making the update permissioned serves as a conservative approach here.

## Dependencies

Dependencies are managed using foundry's system, i.e., git submodules.

Non-standard dependencies:
- `lib/gyro-concentrated-lps-balv2/` - Ad-hoc interface for Gyro pools under Balancer v2, and some related interfaces in the Gyroscope system required for the V2 variant.

The code is formatted using `forge fmt`.

## Deployment & Operation

### Common for Balancer V2 and V3

The contract uses a two-step initialization procedure to avoid a circular deployment dependency of the `UpdatableRateProvider` vs the pool.

1. When deploying the `UpdatableRateProvider`, the deployer specifies the `feed` rateprovider, the admin, and (optionally) the updater; in the V2 variant, they also specify the contracts used to temporarily set the protocol fee during update.
2. They then specify the `UpdatableRateProvider` as the rate provider of the pool and deploy the pool. The rateprovider will work in this state, but the update function is not available (it would revert).
3. The admin then calls `UpdatableRateProvider.setPool()` to connect the rateprovider to the pool. This can only be done once. The update function is then available.

An `UpdatableRateProvider` *must not* be used for more than one pool. We cannot and do not check this.

### Balancer V2 Variant

The Balancer V2 variant of the CLPs cannot differentiate, for the purpose of collecting protocol fees, between swap fees, underlying yield, and rate provider changes. An update of the rateprovider would be registered as yield, which is likely undesirable. To work around this, `UpdatableRateProviderBalV2` performs the following actions:

- It joins the pool with a small amount. This sets the `lastInvariant` state value of the pool that tracks protocol fees.
- It sets the protocol fee to 0, saving the previous value.
- It updates its rateprovider value.
- It exits the pool again to, again, reset `lastInvariant`.
- In then resets the protocol fee to its previous value.

Because of this, the following additional steps are needed for deployment:

4. Governance has to approve the `UpdatableRateProvider` to set the protocol fee on its corresponding pool through the `GovernanceRoleManager`.
5. Someone has to transfer a small amount of all pool tokens to the `UpdatableRateProvider` (for joining and exiting).

### Balancer V3 Variant

For the Balancer V3 variant, it must be ensured that the pool does not take protocol fees on yield (since this would imply protocol fees for upwards updates, but not for downwards updates, which is likely undesired). Nothing else needs to be done.

## Source Tour

- `BaseUpdatableRateProvider` is an abstract base class that contains most of the logic and math and state that is independent of whether it's Balancer V2 or V3.
- `UpdatableRateProviderBalV2` is the concrete derived contract for Balancer V2 pools.
- `UpdatableRateProviderBalV3` is the concrete derived contract for Balancer V3 pools.

## Analysis

We perform some basic analysis to derive the formulas used in `BaseUpdatableRateProvider._updateToEdge()`.

First consider a two-asset pool (2CLP or ECLP). The 3CLP will be a analogous (see below).

In the following, let $r$ be the current rate returned by the feed, call the pool assets x and y (corresponding to asset indices 0 and 1), let $\delta_x$ and $\delta_y$ be the current (pre-update) rates of the pool, and let $\alpha$ and $\beta$ be the corresponding price range of the pool. The parameters $\alpha$ and $\beta$ are available as follows:

- For the ECLP, the two parameters $\alpha$ and $\beta$ are part of the pool configuration.
- For the 2CLP, $\sqrt{\alpha}$ and $\sqrt{\beta}$ are part of the pool configuration, and we compute $\alpha$ and $\beta$ from that.
- For the 3CLP (see below), $\sqrt[3]{\alpha}$ is part of the pool configuration and the pool is always symmetric, i.e., $\beta = 1/\alpha$ and the price range is the same for each of the three asset pairs. We compute $\alpha$ and $\beta$ from this.

 Note that either $\delta_x$ or $\delta_y$ correspond to the current value of the `UpdatableRateProvider` (depending on whether it's associated with asset x or asset y) and the other rate may be given by another rateprovider or may just be 1.

Note also that $\alpha$ and $\beta$ are the lower/upper bound of the price range of the "inner" (post rate-scaling) pool curve. The "outer" values (which are the actual minimal/maximal prices quoted by the pool) corresponding to these are

$$
\begin{align}
\alpha' &:= \alpha \cdot \frac{\delta_x}{\delta_y}
\\
\beta' &:= \beta \cdot \frac{\delta_x}{\delta_y}
\end{align}
$$

We say (and indicate in the `ValueUpdated` event) that the pool is out of range `BELOW` if the true price is below $\alpha'$ and it's out of range `ABOVE` if the true price is above $\beta'$.

### Formulas for `updateToEdge()`

`updateToEdge()` checks that the pool is out of range and then updates the rateprovider such that the pool is just at the corresponding edge of its price range post-update (lower edge if the true price is below the price range pre-update, upper edge if the price is above the price range pre-update). The following formulas are implemented in `BaseUpdatableRateProvider._updateToEdge()`.

If the `UpdatableRateProvider` corresponds to asset x, then the pool is out of range `BELOW` iff

$$
\begin{align}
&& \frac{r}{\delta_y} &< \alpha' = \alpha \cdot \frac{\delta_x}{\delta_y}
\\
\Leftrightarrow&& r / \alpha &< \delta_x
\end{align}
$$

and it is out of range `ABOVE` iff

$$
\begin{align}
&& \frac{r}{\delta_y} &> \beta' = \beta \cdot \frac{\delta_x}{\delta_y}
\\
\Leftrightarrow&& r / \beta &> \delta_x
\end{align}
$$

and by updating $\delta_x$ to the left-hand-side value, we make it such that the current price is exactly on the edge. Note that $\delta_y$ cancels out in the calculation.

Vice versa, if the `UpdatableRateProvider` corresponds to asset y, then the pool is out of range `BELOW` iff

$$
\begin{align}
&& \frac{\delta_x}{r} &< \alpha' = \alpha \cdot \frac{\delta_x}{\delta_y}
\\
\Leftrightarrow && \delta_y &< \alpha \cdot r
\end{align}
$$

and it is out of range `ABOVE` iff

$$
\begin{align}
&& \frac{\delta_x}{r} &> \beta' = \beta \cdot \frac{\delta_x}{\delta_y}
\\
\Leftrightarrow && \delta_y &> \beta \cdot r
\end{align}
$$

and, again, by updating $\delta_y$ to the left-hand-side value, we make it such that the current price is exactly on the edge.

#### 3CLP

The 3CLP is _symmetric_, i.e., the "inner" (post rate-scaling) price range for each of the three prices always satisfies $\beta = 1/\alpha$, and $\alpha$ and $\beta$ are the same for each of the three prices. Because of this, the calculations above are still valid and it does not matter which of the three assets the `UpdatableRateProvider` is attached to. We can therefore simply re-use the above calculations.

To allow some uniformity in the code, `_updateToEdge()` assumes that, in case of the 3CLP, the numéraire asset is asset z.
