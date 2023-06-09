# DynSDT Implementations
*Dynamic Score-Decomposed Tries* which solve the scored prefix completion problem. The C# version is the primary version at the moment. The preliminary TypeScript version in the main repo was created just to match the pseudocode from the paper to help verify the correctness of the pseudocode. The Zig version is still in-development.

Paper: [validark.github.io/DynSDT](https://validark.github.io/DynSDT/), entitled *Heap-like Dynamic Score-Decomposed Tries for Top-k Autocomplete*

Live Demo: [validark.github.io/DynSDT/demo](https://validark.github.io/DynSDT/demo/)

Email autocomplete proof-of-concept: [validark.github.io/DynSDT/web-autocomplete](https://validark.github.io/DynSDT/web-autocomplete/)
  - This uses another TypeScript implementation I made which supports aliasing so multiple names/emails can autocomplete to the same person. [The source code is available here](https://github.com/Validark/DynSDT/tree/paper/web-autocomplete). 

Paper & Demo website code: [/tree/paper](https://github.com/Validark/DynSDT/tree/paper)



Give me a star if you appreciate this work!

Keywords: Query Autocomplete, QAC, type-ahead, ranked autosuggest, top-k autocomplete, trie decomposition, Dynamic Score-Decomposed Trie, trie autocomplete, Completion Trie.
