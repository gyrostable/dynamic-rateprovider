
# Gyroscope Dynamic RateProviders

These are contracts that implement the `RateProvider` interface and are connected to a price feed but do _not_ automatically reflect the current value of the feed. Instead, everyday operation is like a `ConstantRateProvider` that always returns the same stored value. What differentiates these rateproviders from a `ConstantRateProvider` is that they also have an update method by which the stored value can be updated based on the feed. This update is not unconditional, though, to avoid an arbitrage loss to LPers.

The `feed` rateprovider is often a `ChainlinkRateProvider` that pulls prices from chainlink, but it could also be a contract that implements some transformation of oracle feeds (e.g., the quotient of two oracle feeds to get a relative price). In any case, it is assumed that the `feed` returns a live market price.

In the V1 version of the contract, `updateToEdge()` can only be performed when the linked pool is out of range, and then the rate is updated such that the pool is just barely at the respective edge of its price range. In this case, LPers do not incur an arbitrage loss. It is expected that these updates occur rarely.

The rateprovider supports ECLPs in both Balancer V2 and Balancer V3. The Balancer version needs to be indicated in the constructor.

A potential accounting problem occurs if protocol fees are taken on underlying yield while the rateprovider updates. To avoid this, for Balancer V3, the pool must not take protocol fees on underlying yield. For Balancer V2, the rateprovider must be authorized to temporarily set protocol fees to 0.

The update method is permissioned and can only be performed by the respective authorized role. The reason for this is to protect against unknown potential attacks that might be available by performing an update together with some other operation. While we are not aware of any such attack, making the update permissioned serves as a conservative approach here.

## Dependencies

Dependencies are managed using foundry's system (and therefore are installed automatically on clone).

Non-standard dependencies:
- `lib/gyro-concentrated-lps-balv2/` - Ad-hoc interface for the ECLP under Balancer v2.

## Operation

The contract uses a two-step initialization procedure to avoid a circular deployment dependency of the `UpdatableRateProvider` vs the pool.

1. When deploying the `UpdatableRateProvider`, the deployer specifies the chainlink feed and the admin.
2. They then specify the `UpdatableRateProvider` as the rate provider of the pool and deploy the pool. The rateprovider will work in this state, but the update function is not available (it would revert).
3. The admin then calls `UpdatableRateProvider.setPool()` to connect the rateprovider to the pool. This can only be done once. The update function is then available.

An `UpdatableRateProvider` *must not* be used for more than one pool. We cannot and do not check this.

## Source Tour

- `BaseUpdatableRateProvider` is an abstract base class that contains most of the logic and math and state that is independent of whether it's Balancer V2 or V3.
- `UpdatableRateProviderBalV2` is the concrete derived contract for Balancer V2 pools.
- `UpdatableRateProviderBalV3` is the concrete derived contract for Balancer V3 pools.

## Analysis

We perform some basic analysis to derive the formulas used in `BaseUpdatableRateProvider._updateToEdge()` and to illustrate the arbitrage safety.

In the following, let $r$ be the current rate returned by the chainlink feed, call the pool assets x and y (corresponding to indices 0 and 1 in the API functions), let $\delta_x$ and $\delta_y$ be the current (pre-update) scaling rates of the pool, and let $\alpha$ and $\beta$ be the corresponding ECLP parameters. Note that either $\delta_x$ or $\delta_y$ correspond to the current value of the `UpdatableRateProvider` (depending on whether it's associated with asset x or asset y) and the other rate may be given by another rateprovider or may just be 1.

Note also that $\alpha$ and $\beta$ correspond do the "inner" (post rate-scaling) ECLP curve. The "outer" values (which are the actual minimal/maximal prices quoted by the pool) corresponding to these are

$$
\begin{align}
\alpha' &:= \alpha \cdot \frac{\delta_x}{\delta_y}
\\[.7em]
\beta' &:= \beta \cdot \frac{\delta_x}{\delta_y}
\end{align}
$$

We say (and indicate in the `ValueUpdated` event) that the pool is out of range `BELOW` if the true price is below $\alpha'$ and it's out of range `ABOVE` if the true price is above $\alpha'$.

### Formulas for `.updateToEdge()`

`.updateToEdge()` checks that the pool is out of range and then updates the rateprovider such that the pool is just at the corresponding edge of its price range post-update (lower edge if the true price is below the price range pre-update, upper edge if the price is above the price range pre-update). The following formulas are implemented in `BaseUpdatableRateProvider._updateToEdge()`.

If the `UpdatableRateProvider` corresponds to asset x, then the pool is out of range `BELOW` iff

$$
\begin{align}
&& \frac{r}{\delta_y} &< \alpha' = \alpha \cdot \frac{\delta_x}{\delta_y}
\\[.7em]
\Leftrightarrow&& r / \alpha &< \delta_x
\end{align}
$$

and it is out of range `ABOVE` iff

$$
\begin{align}
&& \frac{r}{\delta_y} &> \beta' = \beta \cdot \frac{\delta_x}{\delta_y}
\\[.7em]
\Leftrightarrow&& r / \beta &> \delta_x
\end{align}
$$

and by updating $\delta_x$ to the left-hand-side value, we make it such that the current price is exactly on the edge.

Vice versa, if the `UpdatableRateProvider` corresponds to asset y, then the pool is out of range `BELOW` iff

$$
\begin{align}
&& \frac{\delta_x}{r} &< \alpha' = \alpha \cdot \frac{\delta_x}{\delta_y}
\\[.7em]
\Leftrightarrow && \delta_y &< \alpha \cdot r
\end{align}
$$

and it is out of range `ABOVE` iff

$$
\begin{align}
&& \frac{\delta_x}{r} &> \beta' = \beta \cdot \frac{\delta_x}{\delta_y}
\\[.7em]
\Leftrightarrow && \delta_y &> \beta \cdot r
\end{align}
$$

and, again, by updating $\delta_y$ to the left-hand-side value, we make it such that the current price is exactly on the edge.

### No arbitrage opportunity from `.updateToEdge()`

TODO WIP.

We show that `.updateToEdge()` does not imply any additional arbitrage opportunities. Assume WLOG that the rateprovider is for asset x, there is no rateprovider on asset y, the pool is out of range `BELOW` and initially, the pool may be either in equilibrium (i.e., there is no asset y in the pool) or not. Note that one reason why the pool may _not_ be in equilibrium is a hypothetical attack that sandwiches the update. Under these assumptions, the pre-update value of the rateprovider is $\delta_x$ and the post-update value is $r/\alpha < \delta_x$.

If the pool is in equilibrium pre-update, it consists of only asset x, so the only operation possible is buying asset x from the pool. The update obviously preserves this property. The price quoted pre-update is $\alpha \delta_x > r$, so buying pre-update implies a loss vs. the market price and the price post-update is $r$, so buying post-update does not imply a profit. 

TODO ^^ can prob scrap that.

