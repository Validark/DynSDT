This directory holds the C# implementation of the [*Dynamic Score-Decomposed Trie*](https://validark.github.io/DynSDT/demo).

This code is designed to work as a drop-in replacement to the [*Pruning Radix Trie*](https://github.com/wolfgarbe/PruningRadixTrie)
(and be many times faster).

## Limitations of this implementation

- This implementation differs a bit from the one in [the paper](https://validark.github.io/DynSDT/) because Nodes are implemented as structs, and C# doesn't support raw pointers unless one wants to deal with unsafe code and "pointer pinning". This is why whenever a struct is updated all of its copies in various places are updated as well.
- ${\rm G{\small et}T {\small op}}k {\rm T{\small erms}F{\small or}P{\small refix}}(p,\ k)$ allocates a list of size ${\rm M{\small in}}(k,\ c)$, where $c$ is the number of total string terms in the data structure. So if you pass in `int.MaxValue` to $k$ you're going to allocate $c$ slots for the result array.
- There are some differences from the original PruningRadixTrie implementation:
  - `termCount` is an `int`, not a `long`
  - The following public members are not supported: `termCountLoaded UpdateMaxCounts FindAllChildTerms BinarySearchComparer BinarySearchComparer`
  - There is no `Node.cs` file (so we can have a single `using score_int = System.Int64;` directive), so if you literally drag and drop the `PruningRadixTrie` files onto your [*Pruning Radix Trie*](https://github.com/wolfgarbe/PruningRadixTrie) files, you will have to delete the old `Node.cs` file.
  - In the `csproj` file, `PruningRadixTrie.csproj` has the `TargetFramework` updated from `netstandard2.0` to `netstandard2.1`.
  - if ${\rm S{\small et}}(t,\ s)$, ${\rm A{\small dd}T{\small erm}}(t,\ s)$, or ${\rm D{\small elete}}(t)$ receive null or the empty string for term $t$, it is a no-op.
    - I'm pretty sure nobody actually wants the empty string in the data structure anyways...

## Tradeoffs

- Each node stores an array of branch points rather than a left-child and right-sibling. This makes the data structure a bit smaller (for the Wikipedia dataset) but makes construction a bit slower and querying a bit faster (in non-repetitive tests).  I have yet to implement ${\rm S{\small et}}$, ${\rm A{\small dd}T{\small erm}}$, or ${\rm D{\small elete}}$ in LCRS but I suspect they could be faster because:
  - They would require 0 allocations to modify nodes that are already present.
    - When adding a new node, only that new node would need to be allocated.
  - ${\rm D{\small elete}}$ would take 0 allocations, but of course makes one node garbage.
    - The only way to get around this would be to have some kind of pool of unused nodes, however, I've heard it is usually better to just put your faith in C#'s automagic memory management.
- Nodes are value types, written directly into their slots in arrays. This reduces memory consumption a bit and improves memory locality, improving speed somewhat.
  - Unfortunately, that means we can not have a pointer that points directly to a Node (without unsafe code and "pinning" C#'s garbage collector).
  - This means we have to keep a reference to `parentPeers` and sometimes `grandPeers` in the code, so we can update the necessary value types where they actually are in memory.
  - This means we have to watch out for cache invalidation in our "running maximums list" in the [exact match found (demotion)](https://validark.github.io/DynSDT/#exact-match) algorithm.
    - Luckily, there is actually only one list of branch points (called `peers` in the code) that can become stale, and that's when the `parentPeers` is the same array as the next one in the "running maximums list" (inverse checked on line 1109 ****& updated on line 1133) https://github.com/Validark/DynSDT/blob/a50b4d17e269230c3b68c65258b09c31b0027b6f/c%23/PruningRadixTrie/PruningRadixTrie.cs#L1106-L1134
      - This makes sense because the "running maximums list" holds successively deeper layers along a single path. E.g. the running maximums list might look like $[1,\ 2,\ 3]$, where $2$ was inserted into $1$ and $3$ was inserted into $2$, in which case inserting into $1$ invalidates $2$ and inserting into $2$ invalidates $3$. If it instead were $[1,\ 3,\ 5]$, then inserting into $1$ cannot invalidate $3$ and inserting into $3$ cannot invalidate $5$. (The integers are not LCP's, they are layers.)

## Preprocessor directives
This implementation has a few preprocessor directives which can toggle behavior:

|directive|description|
|:-:|:-:|
|COMPRESS_STRINGS|deletes the prefix of each key which is implied by its path from the root, reducing memory usage|
|FORCE_STATIC|makes Set/Delete/AddTerm private, enables hashMaps which skip the first 2 characters, and enables string interning (when COMPRESS_STRINGS is also used)|
|DEBUG_METHODS|enables some methods that allow for testing that a given function produces the right output|
|INVARIANT_CHECKS|enables some runtime checks which are impossible to trigger unless there is a major flaw in logic somewhere. Mainly for debugging/fuzzing.|
