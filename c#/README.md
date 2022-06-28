This directory holds the C# implementation of the [*Dynamic Score-Decomposed Trie*](https://validark.github.io/DynSDT/demo).

This code is designed to work as a drop-in replacement to the [*Pruning Radix Trie*](https://github.com/wolfgarbe/PruningRadixTrie)
(and be many times faster). Note that this version does not have a separate `Node.cs` file
(so we can have a single `using score_int = System.Int64;` directive), so if you literally drag and drop
the `PruningRadixTrie` files onto your [*Pruning Radix Trie*](https://github.com/wolfgarbe/PruningRadixTrie)
files, you will have to delete the old `Node.cs` file. Note: the only change to the `csproj` file is that
`PruningRadixTrie.csproj` has the `TargetFramework` updated from `netstandard2.0` to `netstandard2.1`.

## Preprocessor directives
This implementation has a few preprocessor directives which can toggle behavior:

|directive|description|
|:-:|:-:|
|COMPRESS_STRINGS|deletes the prefix of each key which is implied by its path from the root, reducing memory usage|
|FORCE_STATIC|makes Set/Delete/AddTerm private, enables hashMaps which skip the first 2 characters, and enables string interning (when COMPRESS_STRINGS is also used)|
|DEBUG_METHODS|enables some methods that allow for testing that a given function produces the right output|
|INVARIANT_CHECKS|enables some runtime checks which are impossible to trigger unless there is a major flaw in logic somewhere. Mainly for debugging/fuzzing.|

The reason why this implementation differs a bit from the one in [the paper](https://validark.github.io/DynSDT/)
is that Nodes are implemented as structs, and C# doesn't support raw pointers unless one wants to
deal with unsafe code and "pointer pinning". This is why whenever a struct is updated all of its copies
in various places are updated as well.

#### TODO: Finish polishing tests and upload them
