#import "@preview/drafting:0.2.1": margin-note, inline-note
#import "@preview/diverential:0.2.0": *
#import "@preview/zero:0.3.1": num

// We are making 'prose' (citet) the default to be consistent with the other kinds of references. You can use #citep[@mycitation] to use the normal one.
#set cite(form: "prose")
#let citep(citation) = {
  set cite(form: "normal")
  citation
}

// SOMEDAY maybe turn off the auto-fraction feature. Right now, there's no good package that does what I want (and still lets me use fractions) :( - I could do it using a little post-processing but prob does more bad than good. (e.g. I only want to do this in math, not in text or URLs or ...)
// Maybe I can do a really funky show rule?
// NB this one doesn't work b/c then I can't use *any* fractions, which breaks derivatives, for instance. https://github.com/typst/typst/issues/3203#issuecomment-1893279410

// Example to format dynamically computed values. Could use this for simple calculations.
// (and of course just use num for formatting.)
// #let val = 12345 + 1/3
// #num(round: (mode: "places"), str(val))

// see https://typst.app/universe/package/ctheorems
// TODO make these styles less weird. Wtf.
#import "@preview/ctheorems:1.1.3": *
#show: thmrules
// mythm is a mix between thmbox and thmplain (but mostly plain: I don't want colored boxes or stuff)
// SOMEDAY also set the inset to 0 (relevant is left/right). OR increase it a bit I guess.
#let mythm = thmplain.with(namefmt: x => [(#x)], titlefmt: strong, base_level: 0)
#let myitthm = mythm.with(bodyfmt: x => text(style: "italic", x))

#let definition = mythm("definition", "Definition")
#let proposition = myitthm("proposition", "Proposition")
#let theorem = myitthm("theorem", "Theorem")
#let lemma = myitthm("lemma", "Lemma")
#let corollary = myitthm("corollary", "Corollary")
#let proof = thmproof("proof", "Proof")
#let notation = mythm("notation", "Notation").with(numbering: none)

// Extract the theorem type (Lemma, Theorem, etc. from a reference). Can also be used for Figure, Table, etc., but less useful. In lowercase.
// Usage: The #ref_kind[@my_thm] can be interpreted as ...
#let ref_kind(r) = {
  show ref: it => lower(it.element.supplement)
  r
}

#let citeauthor(r) = {
  set cite(form: "author")
  r
}

#let itodo(cnt) = inline-note(cnt, rect: rect.with(
  inset: .5em, radius: 0.5em, fill: orange.lighten(90%)
))
#let mtodo(cnt) = margin-note(text(size: 9pt, par(justify: false, cnt)))
#let todo(cnt) = itodo(cnt)

#let dom = math.op("dom", limits: false)

#let blank = $thin circle.filled.tiny thin$

// Table helper
#show table.cell.where(y: 0): strong

#set page(
  paper: "a4",
  numbering: "1",
  margin: (
    x: 3.5cm
  )
)
#set text(
  // SOMEDAY nicer font. And generally prettier styling. And 1.5 line height
  // I think we want everything a bit smaller.
  // SOMEDAY add a bit more space below section headers
  // font: "New Computer Modern",
  // font: ("Helvetica Neue", "Libertinus Serif"),
  font: "TeX Gyre Heros",
  // Experimental: Add just a bit of space between characters to make it more "airy"
  tracking: 0.2pt,
  // weight: "light",
  // font: "Roboto",
  // font: "Inter",
  size: 10pt,
)

// Workaround for https://github.com/typst/typst/issues/366
// Math text doesn't by default use the text font. (and there's no convenient command)
#let mtext(c) = {
  set text(font: "TeX Gyre Heros")
  c
}

// TODO I really want no par spacing but 0pt is not the right setting. Wtf.
#set par(
  justify: true,
  first-line-indent: 1.5em,
  spacing: 1.3em,
  leading: 0.9em,
)
#set heading(numbering: "1.")

// Usage: When you wanna start the appendix:
// #appendixtitle("Appendix")
// #show: appendix
#let appendix(body) = {
  set heading(numbering: "A", supplement: [Appendix])
  counter(heading).update(0)
  body
}
#let appendixtitle(txt) = {
  set heading(numbering: none, level: 1)
  heading(txt)
}


#let title = [Updatable Rate-Scaling for the 3CLP]

#let abstract = [We discuss how to make the 3CLP updatable by adjusting token rates using a special updatable rate provider. This allows the pool to adjust its price range when one or several of its prices are out of range and enables it to be used for volatile pairs like WETH/WBTC/USDC.]

#place(
  top + center,
  float: true,
  scope: "parent",
  clearance: 2em,
)[
  #align(center, text(20pt)[
    // *#title*
    #par(justify: false, text(hyphenate: false, weight: "bold", title))
  ])
  #align(center)[
    // Manual footnote. NB for '*' specifically we don't need super. (this is a bit of a bug)
    Steffen Schuldenzucker, Ariah Klages-Mundt\*
  ]
  #align(center, datetime.today().display("[month repr:long] [day padding:none], [year]"))
  #box(
      width: 90%,
      inset: 1em,
  )[
    // #text(size: 9pt)[#abstract]
    #align(left, par(leading: .6em, justify: true, text(size: 9pt, abstract)))
  ]
]

// Manual footnote b/c it's broken in float titles. :(
#place(footnote(numbering: it => "", {[\*] + [Researchers at Superluminal Labs, a software development company working in the Gyroscope ecosystem. #link("steffen@gyro.finance"), #link("ariah@gyro.finance")]}))
#counter(footnote).update(0)

= Setting

#let pxz = $p_(x\/z)$
#let pyz = $p_(y\/z)$
#let Pxz = $P_(x\/z)$
#let Pyz = $P_(y\/z)$

Assume that there are three assets with balances $t = (x, y, z)$ with rates $delta = (delta_x, delta_y, delta_z)$ attached. Fix some parameter $alpha in (0, 1)$. The rate-scaled 3CLP constructs a 3CLP curve with respect to the rate-scaled balances $t^delta := (delta_x x, delta_y y, delta_z z)$ and allows trading along this curve with rate-scaled balances. For example, when swapping x to y, a swap amount $Delta x$ would be scaled up to $Delta x^delta := delta_x dot Delta x$, then a corresponding rate-scaled swap amount $Delta y^delta$ is computed along the rate-scaled 3CLP curve, and this amount is scaled back to $Delta y := Delta y^delta \/ delta_y$.

In the updatable version of this setup, one or more of the rates $delta$ are controlled by a manager contract (the _orchestrator_) and can be updated if the pool is out of range of the current market prices. Assume that we are given oracle prices $p = (p_x, p_y, p_z)$. The quote asset of these prices does not matter since we will be using relative prices exclusively.
We will assume in the following WLOG that (1) the numeraire is asset z and the price vector is
$
  p = (pxz = p_x / p_z, med pyz = p_y / p_z)
$
and we assume (2) that the updatable rate provider controls the rates $delta_x$ and $delta_y$. If this is not the case, we simply need to rotate our asset names.#footnote[
   Note here that the 3CLP is symmetric as well, so we do not need to transform any pool parameters when we rename assets. We could also assume for this exposition WLOG that and $delta_z = 1$, i.e. asset z does not have a rate provider, but we do not here. Our implementation _does_ establish this, though.
]

We can transform prices between rate-scaled and actual space. Specifically, let
$
  p^delta = (delta_z / delta_x pxz, med delta_z / delta_y pyz)
$
be the rate-scaled vector of oracle prices.

= Feasible pool prices and equilibrium

We now need to consider what it means for the 3CLP to be "out of range". Label the rate-scaled ("inner") pool spot prices offered by the pool $P^delta = (Pxz^delta, Pyz^delta)$. Note that the third pair price, $P_(x\/y)^delta$, can be left out because the pool's internal prices are always arbitrage-free, i.e., $P_(x\/y)^delta = Pxz^delta \/ Pyz^delta$. The corresponding "outer" spot prices exhibited by the pool to traders are
$
  P = (Pxz = delta_x / delta_z Pxz^delta, med Pyz = delta_y / delta_z Pyz^delta)
  .
$
In this exposition, we will be mostly working in rate-scaled space, i.e., with the rate-scaled prices $P^delta$ and $p^delta$.

Due to its structure and parameters, the pool can only attain a bounded set of $P^delta$ vectors; we call these _feasible pool price vectors_. This set is _not_ simply the square $[alpha, 1\/alpha] times [alpha, 1\/alpha]$ but through the interaction of assets, it looks like @fig-representable-prices. Specifically, the set of feasible pool price vectors is the intersection of three conditions, labeled "$x >= 0$", "$y >= 0$", and "$z >= 0$" in the figure (see below for the reasons for these labels).

For every vector of true (rate-scaled) prices, there is a unique _equilibrium pool price vector_ $P^delta (p^delta)$ where no arbitrage exists, and it can be computed by projecting $p^delta$ onto the boundary of the feasible region using a certain algorithm #citep[@kmsr2023design[Section~5.3]].#footnote[
  Note that the $delta$ value in $P^delta (...)$ does not refer to any specific $delta$ but is merely notation to indicate that we refer to rate-scaled pool prices. The function $P^delta (...)$ does not depend on the scaling rates $delta$.
] In the previous reference, rate scaling is not considered, but arbitrage-freeness is not affected by rate scaling.#footnote[
  The _size_ of an arbitrage opportunity, if there is one, is affected by rate scaling, though, up to a factor of $max_((i,j) in {x,y,z}) delta_i \/ delta_j$.
]
The pool is _out of range_ if the current (rate-scaled) prices $p^delta$ are not feasible, or equivalently $P^delta (p^delta) != p^delta$.

Based on the reserve balances in the pool, the pool also exhibits an _actual_ current vector of spot prices $P^delta (t^delta)$. The pool exposes an arbitrage opportunity iff $P^delta (t^delta) != P^delta (p^delta)$. In the following, we will assume that this is not the case (i.e., $P^delta (t^delta) = P^delta (p^delta)$), following the usual argument that any such opportunity would quickly be taken by arbitrageurs.#footnote[
  In the presence of swap fees, small price divergences (up to the fee) are not exploitable by arbitrageurs and therefore the the equality will only hold approximately. This is ignored here.
]

#figure(
  image(
    "3clp-price-space.png",
    width: 80%,
  ),
  placement: auto,
  caption: [Space of feasible pool prices in the 3CLP. This is the intersection of three sets given by the condition that all implied balances need to be non-negative. Note that the axes should be labeled $Pxz^delta$ and $Pyz^delta$ instead of $pxz$ and $pyz$, respectively, in our notation here. The black square is $[alpha, 1\/alpha] times [alpha, 1\/alpha]$. Note that the lower corner $(alpha, alpha)$ of the square is not feasible, as are many other points in the square.],
)<fig-representable-prices>

= Rate provider update

Assume now that we find ourselves in a situation where the pool is in equilibrium with the external market but out of range, i.e., $P^delta (t^delta) = P^delta (p^delta) != p^delta$. In this situation, we have for at least one of the three asset pairs that no trading is possible in either direction at the current global market price. Our goal is now to update the rates $delta_x$ and $delta_y$ to new rates $delta'_x$ and $delta'_y$ such that the following two conditions hold:

#[
#set enum(numbering: n => strong(numbering("1.", n)))
+ *Arbitrage-freeness.* Updating the rates does not introduce an arbitrage opportunity.
+ *Efficiency.* The pool is in range after the update.
]

We show in the remainder of this paper that these two conditions can be achieved by chosing $delta'$ in such a way as to move the rate-scaled market prices to the current equilibrium prices, i.e., to establish
$
  p^(delta') = P^delta (p^delta).
$

This is achieved by choosing
$
  delta'_x &:= delta_z dot pxz / (Pxz^delta (p^delta)) &= delta_x dot pxz^delta / (Pxz^delta (p^delta))
  \
  delta'_y &:= delta_z dot pyz / (Pyz^delta (p^delta)) &= delta_y dot pyz^delta / (Pyz^delta (p^delta))
  \
  delta'_z &:= delta_z.
$

Observe that, if $p^delta$ is already feasible (i.e., $P^delta (p^delta) = p^delta$), then the terms cancel out to yield $delta'_x = delta_x$ and $delta'_y = delta_y$, i.e., there is no update, as expected. Otherwise, there will be some change. @fig-p-delta-projections illustrates some further example projections from $p^delta$ to $p^(delta') = P^delta (p^delta)$. Essentially, we always project onto the closest point at the boundary along the direction(s) of the condition(s) that is/are not satisfied. Note that this projection is the same as equilibrium calculation in @kmsr2023design[Section~5.3].

#figure(
  image(
    "p-delta-projections.svg",
    width: 100%,
  ),
  placement: auto,
  caption: [Some example projections of the rate-scaled price vector $p^delta$ under the original rates to the new rates vector $p^(delta')$, which coincides with price equilibrium computation. The set labeled "$x >= 0$" is also denoted $T_x$ below, and analogously for $y$ and $z$.],
)<fig-p-delta-projections>

The remainder of this document is to show that this update is indeed arbitrage-free and efficient. To do this, we first show that the update does not affect rate-scaled prices.

= No change in rate-scaled prices

The updated rates $delta'$ need to be carefully chosen because the actual (not rate-scaled) balances of the pool do (of course) not change due to our rate provider update while the rate-scaled pool balances (which determine the prices exhibited by the "inner" pool curve) do, from $t^delta$ to $t^(delta')$. Because of this, for general $delta'$, an update could introduce an arbitrage opportunity. We need to show that this is not the case for our choice of $delta'$ and to do this, we need to consider the interaction between balances and prices in greater detail.

Let $P^delta (t^delta)$ be the rate-scaled pool prices exhibited at rate-scaled balances $t^delta$. See @kmsr2022concentrated[Section~3] for the corresponding formulas and note that there is a 1:1 correspondence between $P^delta$ vectors and pairs $(t^delta, L)$, where $L$ is the pool invariant, and $t^delta (P^delta, L)$ scales linearly in $L$.

Our main lemma towards arbitrage-freeness and efficiency is to observe that the update from $delta$ to $delta'$ does not change the rate-scaled pool prices.

#let interior(x) = $#x ^ circle.small$
#let boundary(x) = $partial #x$

#lemma[
  $
    P^delta (t^(delta')) = P^delta (t^delta)
  $
]<lem-pool-price-preservation>
#proof[
  Denote the interior of a set $A$ as $interior(A)$ and the boundary $boundary(A)$.
  @kmsr2023design[Appendix~A.2] represent the set of feasible pool price vectors as the intersection of three sets $T_x inter T_y inter T_z$ such that we have $P^delta (p^delta) in T_x inter T_y inter T_z$ and
  $
    (ast) quad && P^delta (t^delta) in boundary(T_x) <=> x = 0
  $
  and likewise for the other assets.

  We perform case distinction to show that $t^delta' = lambda dot t^delta$ for some scalar $lambda > 0$. It is easy to see that this implies the statement of the lemma.

  First, if $P^delta (p^delta) in interior(T_x) inter interior(T_y) inter interior(T_z)$, then this implies that $p^delta$ is already feasible, so by the above discussion, $delta' = delta$ and there is no change.

  Second, if $P^delta (p^delta) in boundary(T_i) inter boundary(T_j) inter interior(T_j)$ for some permutation ${i,j,k}={x,y,z}$, then by (#sym.ast), two of the asset balances $x, y, z$ are zero and then $t^delta'$ and $t^delta$ are trivially related by a scalar.

  Third, if $P^delta (p^delta) in boundary(T_i) inter interior(T_j) inter interior(T_k)$, we perform case distinction over $i$.

  If $i = x$, then we have $Pyz^delta (p^delta) = pyz^delta$ #citep[@kmsr2023design[Algorithm~1 and Theorem~1]] and therefore $delta'_y = delta_y$, and also $x=0$ by (#sym.ast). This implies $t^delta' = t^delta$ and in particular, they are related by the scalar 1.
  
  If $i = y$, the analogous statement applies.

  If $i = z$, then $(Pxz^delta (p^delta)) / pxz^delta = (Pyz^delta (p^delta)) / pyz^delta$ (see the algorithm and theorem again) and therefore $delta'_x / delta_x = delta'_y / delta_y$, and again by (#sym.ast) we have $z=0$. This again implies the scaling property.

  This concludes our case distinction because $boundary(T_x) inter boundary(T_y) inter boundary(T_z) = emptyset$.
]

= Proving the two core properties

We can now prove the two core properties.

#theorem[
  The update from $delta$ to $delta'$ is arbitrage-free and efficient.
]
#proof[
  We have
  $
    P^delta (t^delta') = P^delta (t^delta) = P^delta (p^delta) = p^delta' = P^delta (p^delta')
  $
  where
  - the first equality is @lem-pool-price-preservation,
  - the second is by assumption since we assume that the pool was in equilibrium before the update,
  - the third is by choice of $delta'$,
  - and the fourth is because $p^delta'$ is feasible because it is chosen equal to the feasible price vector $P^delta (p^delta)$.

  This proves arbitrage-freeness because the (rate-scaled) pool prices post-update $P^delta (t^delta')$ are equal to the equilibrium (rate-scaled) pool prices $P^delta (p^delta')$, i.e., the pool is in equilibrium post-update, i.e., there is no arbitrage opportunity. Efficiency follows because these prices are also equal to the (rate-scaled) market prices $p^delta'$.
]

// Following section commented out for now. We do not use this constrained version, I don't have any results here. More of theoretical interest.
/*
= Variant when only one rate provider is updatable

#todo[This section should be reframed or removed. We don't do this anymore. Should maybe be a remark. Yeah should.]

In a variant of our setup, we may be in a situation where only one rate (say $delta_x$) is updatable and both $delta_y$ and $delta_z$ are either constant or given externally. This could arise, e.g., for a WETH/USDC/USDT pool or a WBTC/wstETH/WETH pool, etc. We note that 3CLP where one leg is stable will typically not be very efficient since, because of the 3CLP's symmetry, the price range on one of the legs will always be suboptimal. Let's assume, though, that we find ourselves in such a situation (e.g., we have concluded that despite a suboptimal stable liquidity profile, the trading demand makes such a 3CLP worth it).

First, note that the calculations laid out here are fundamentally true: independent of which of the rates we can control, the unique arbitrage-free and efficient update is to establish $p^delta' = P^delta (p^delta)$. Therefore, we need to compromise on one of these dimensions if we cannot choose $delta'$ 
freely. 
// TODO how would one actually prove uniqueness here?
// Then this probably makes a nice remark.

#text(red)[*WIP OPEN.* I think you can't do much for some cases (basically everything but $(T_y union T_z) without T_x$). For some cases, the result will just be inefficient, but for some others, no arbitrage-free nontrivial update seems to exist b/c you have to move along the $pyz$ line or along the diagonal. I didn't check the effect through $P^delta (t^delta')$ yet so something _might_ be there. For (say) WETH/USDT/USDC, we may of course assume that $pyz$ is close to 1, so the arbitrage introduced is small. (it's arbitrage-free if $pyz=1$).]
*/

= Remarks

The two-asset case can be seen as a trivial special case of the 3-asset construction laid out here: if we only have two assets, we would usually have an updatable rate provider on only one asset (say, x) and we would update it such that the pool moves just to the edge of its price range (which is a one-dimensional interval for two assets). This can be viewed as computing the equilibrium price (which is either the current price if the pool is in range or one of the two edges of the price range if it's not) and then scaling the price in the same way as we did here.

Our construction should also generalize to other multi-asset pool types beyond the 3CLP, and to more than 3 assets. The only place where we used knowledge of the details of the pool curve was @lem-pool-price-preservation. We feel that the properties that are used in the proof should hold for any sufficiently well-formed AMM, though. Specifically, any AMM should satisfy that certain balances are 0 at the boundary of its feasible price region and the direction of the projection should correspond to a set of equilibrium conditions that are violated. A variant of the proof of @kmsr2023design[Lemma~1 in Appendix~A.2] might be helpful to derive a general form for this. This might also yield a general algorithm for equilibrium computation.

Our update always preserves a state where some of the pool balances are 0, meaning that even post-update, these assets can be sold to the pool (at market spot prices) but not bought. This form of an update therefore relies on later price movements to move the market price fully back into the feasible range. This is the best we can achieve while keeping the real (non-scaled) pool balances the same. An extension could assume that during the update procedure, we can trade at (or close to) market prices at some other market venue; then, we would essentially be able to update the the rates arbitrarily to move the pool to a better liquidity region beyond the edge of the price range. In practice, liquidity in other venues and the costs of trading would have to be carefully traded off against improved availability of the pool.

#bibliography("references.yml", style: "harvard-cite-them-right")

