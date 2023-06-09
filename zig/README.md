## :construction: WIP: Under development :construction:

This is the product of a lot of experimentation, testing out new ideas, and a lot of looking at godbolt. The code is not polished, and although I have removed some of the chicken scratch, some remains. If you are wondering why I have custom version of mem.zig and MultiArrayList.zig it is because those standard libraries do not yet support my use-cases properly. I will delete those libraries once the standard library includes the functionality I need. (see https://github.com/ziglang/zig/pull/15982)

---

This is an implementation of an Dynamic Score-Decomposed Trie.
demo: https://validark.github.io/DynSDT/demo/
paper: https://validark.github.io/DynSDT/

This implementation does not support empty string queries, because they are probably not useful in practice.

This particular library currently has 2 different data layouts for the structure:
	- LCRS-style of representing nodes (i.e., each node has a `next` and a `down` pointer to other nodes)
	- typical array-based style of implementing the structure

The array version may be more cache efficicent due to less pointer-chasing (since we can have forward iterators to find `down` nodes). The LCRS version on the other hand needs to pointer chase for both the `next` and `down` nodes. However, the LCRS version is a lot easier to manage in terms of dynamically updating scores, because rearranging the structure can be done with zero allocations. The only allocations that may occur are when adding genuinely new data. An array-backed implementation requires a lot of arrays to be mutated or replaced, however this would be better for multithreaded environments where you want multiple threads to be able to modify the structure in a lock-free manner (not implemented... yet).

<!-- The disadvantage is that this structure would probably be less than ideal if it was to be shared in a
multi-threaded setting. The best option in that setting might be to use multiple structures, or
consider using a lock-free implementation that relies on arrays of nodes, such that the bottommost-
changed array and its parents up to the root can be copied and then the root pointer can be updated
atomically to the new copy, or the work can be repeated if another thread updated the structure first.
I suppose one _could_ dream up a similar scheme with the LCRS linked-lists, but that would be pretty crazy. -->
