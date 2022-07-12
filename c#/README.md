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

## Preprocessor directives
This implementation has a few preprocessor directives which can toggle behavior:

|directive|description|
|:-:|:-:|
|COMPRESS_STRINGS|deletes the prefix of each key which is implied by its path from the root, reducing memory usage|
|FORCE_STATIC|makes Set/Delete/AddTerm private, enables hashMaps which skip the first 2 characters, and enables string interning (when COMPRESS_STRINGS is also used)|
|DEBUG_METHODS|enables some methods that allow for testing that a given function produces the right output|
|INVARIANT_CHECKS|enables some runtime checks which are impossible to trigger unless there is a major flaw in logic somewhere. Mainly for debugging/fuzzing.|
