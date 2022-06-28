//	deletes the prefix of each key which is implied by its path from the root, reducing memory usage
//#define COMPRESS_STRINGS

//	makes Set/Delete/AddTerm private, making the structure static
//	enables skip1/skip2 hashMaps, which allow for quicker trie traversal for the first two characters
//	enables string interning (when COMPRESS_STRINGS is also used)
//#define FORCE_STATIC

//	enables some Debug methods that allow for testing that a given function produces the right output
//#define DEBUG_METHODS

//	enables some runtime invariant checks which are impossible to trigger unless there is a major flaw in logic somewhere. For debugging/fuzzing
//#define INVARIANT_CHECKS

using System;
using System.Diagnostics;
using System.Collections.Generic;
using score_int = System.Int64; // the size of our score integers

namespace PruningRadixTrie
{
/// <summary> A node in the trie, containing a string key, numeric score, and array of peers.
/// </summary>
public struct Node
{
	public readonly score_int score;
	public readonly String key;

	public (Node node, int LCP)[] peers; // should never be null besides empty root case

	public Node(String key, score_int score)
	{
		this.key = key;
		this.score = score;
		this.peers = Array.Empty<(Node, int)>();
	}

	public Node(String key, score_int score, (Node, int)[] peers)
	{
		this.key = key;
		this.score = score;
		this.peers = peers;
	}

	public override String ToString() => key + " " + score;
}

public struct AltPtr
{
	public static readonly IComparer<AltPtr> Comparer = Comparer<AltPtr>.Create((a, b) => a.peers[a.index].node.score.CompareTo(b.peers[b.index].node.score));
	public (Node node, int LCP)[] peers;
	public int index;

#if COMPRESS_STRINGS
	public String key;
#endif

	public override String ToString()
	{
		if (index < peers.Length)
		{
			var node = peers[index].node;
			return node.key == null ? "null" :
			#if COMPRESS_STRINGS
				key.Substring(0, peers[index].LCP) +
			#endif
				node.ToString();
		}
		return "null";
	}
}

public struct AltPtr2
{
	public (Node node, int LCP)[] peers;
	public int index;

	public override String ToString()
	{
		if (index < peers.Length)
		{
			var node = peers[index].node;
			return node.key == null ? "null" : node.ToString();
		}
		return "null";
	}
}


// This BoundedPriorityDeque is one of two things:
// isBasic:
// 		true -> an insertion-sorted array.
//		false -> a Symmetric Min-Max Heap
//
// Symmetric Min-Max Heap Paper:
// https://liacs.leidenuniv.nl/~stefanovtp/courses/StudentenSeminarium/Papers/AL/SMMH.pdf
// When k is small, an insertion-sorted array is significantly faster than a
// Symmetric Min-Max Heap because the constant factors associated with more complex
// code ends up dominating the run-time for small inputs.
// This makes sense because insertion sort is the fastest sorting algorithm for
// small inputs.

// Symmetric Min-Max Heap:
// insert: Θ(log n)
// insert+delete-min: Θ(log n)
// extract-max: Θ(log n)

// We only expose extract-max without replacement and extract-min with replacement.
// This implementation does not allow one to switch which side gets popped.
// If you try to take this implementation for other projects, make sure you check
// the comments below. Also keep in mind that the extract methods do not write
// default(T) to `data[--len]`. For this module, it isn't necessary because these
// DEPQ's are all (available to be) trashed at the end of the method they're used in.
// If you port this somewhere where the DEPQ's are more persistent, consider overwriting
// `data[--len]` with default(T).
static class BoundedDEPQ<T>
{
	// public static T popMaxBasic(T[] data, ref int len) => data[--len];

	// I tried filling the array from right to left so we avoid shifting nodes
	// right for the first `k` push operations but for some reason it was slower :/

	public static T heapPopMax(T[] data, ref int len, IComparer<T> cmp, T replacement)
	{
		if (len <= 1) return replacement; // If the length is 0 or 1, there's no resifting to do
		var targetIndex = 1;
		var old = data[targetIndex];
		var candidate1 = (targetIndex * 2) | 1;
		var candidate2 = candidate1 + 2;

		while (candidate1 < len)
		{
			var lower = candidate2 >= len || 0 < cmp.Compare(data[candidate1], data[candidate2])
				? candidate1
				: candidate2;

			data[targetIndex] = data[lower];
			targetIndex = lower;
			candidate1 = (targetIndex * 2) | 1;
			candidate2 = candidate1 + 2;
		}
		heapifyUp(data, len, cmp, replacement, targetIndex);
		return old;
	}

	public static T heapPopMin(T[] data, int len, IComparer<T> cmp, T replacement)
	{
		var targetIndex = 0;
		var old = data[targetIndex];
		var candidate1 = (targetIndex + 1) * 2;
		var candidate2 = candidate1 + 2;

		var c = candidate1 + candidate2 + 3;

		while (candidate1 < len)
		{
			var lower = candidate2 >= len || 0 > cmp.Compare(data[candidate1], data[candidate2])
				? candidate1
				: candidate2;

			data[targetIndex] = data[lower];
			targetIndex = lower;
			candidate1 = (targetIndex + 1) * 2;
			candidate2 = candidate1 + 2;
		}
		heapifyUp(data, len, cmp, replacement, targetIndex);
		return old;
	}

	// public static void heapPush(T element)
	// {
	// 	// if (capacity > 0) { // (we check this in-line in the main function)
	// 		if (len == capacity)
	// 		{ // when full, pop the minimum element automatically if we insert
	// 			if (0 < cmp.Compare(element, data[0]))
	// 				heapPopMin(element);
	// 		}
	// 		else
	// 		{
	// 			heapifyUp(data, len, cmp, element, len);
	// 			len++;
	// 		}
	// 	// }
	// }

	public static void heapifyUp(T[] data, int len, IComparer<T> cmp, T element, int targetIndex)
	{
		{ // make this element is properly ordered with its sibling
			var sibling = targetIndex ^ 1;

			if (sibling < len &&
				(sibling > targetIndex
					? cmp.Compare(element, data[sibling]) > 0
					: cmp.Compare(element, data[sibling]) < 0)
			)
			{
				data[targetIndex] = data[sibling];
				targetIndex = sibling;
			}
		}
		var leftUncleIndex = (targetIndex / 2 - 1) & ~1;
		var rightUncleIndex = leftUncleIndex | 1;

		if (rightUncleIndex > 0)
		{
			if (0 > cmp.Compare(element, data[leftUncleIndex]))
			{
				do
				{
					data[targetIndex] = data[leftUncleIndex];
					targetIndex = leftUncleIndex;
					leftUncleIndex = (targetIndex / 2 - 1) & ~1;
				} while (leftUncleIndex >= 0 && 0 > cmp.Compare(element, data[leftUncleIndex]));
			}
			else if (0 < cmp.Compare(element, data[rightUncleIndex]))
			{
				do
				{
					data[targetIndex] = data[rightUncleIndex];
					targetIndex = rightUncleIndex;
					rightUncleIndex = (targetIndex / 2 - 1) | 1;
				} while (rightUncleIndex > 0 && 0 < cmp.Compare(element, data[rightUncleIndex]));
			}
		}

		data[targetIndex] = element;
	}

	private static int HeapToStringHelper(T[] data, int len, String[] lines, int i, int level, int endPadding)
	{
		if (i >= len) return 0;
		var element = (data[i] == null ? "_" : data[i].ToString());
		var leftPadding = HeapToStringHelper(data, len, lines, (i + 1) * 2, level + 1, element.Length);
		var rightPadding = HeapToStringHelper(data, len, lines, ((i + 1) * 2) | 1, level + 1, endPadding);
		lines[level] = lines[level] + new String(' ', leftPadding)
			+ element + new String(' ', rightPadding + endPadding);
		return leftPadding + element.Length + rightPadding;
	}

	// I'm genuinely surprised this actually worked on the first try
	// Based upon https://github.com/geoffleyland/lua-heaps/blob/master/lua/binary_heap.lua#L138
	public static String HeapToString(T[] data, int len)
	{
		var levels = 0;
		// shout-out to people who don't do logarithms on integers
		// this is equivalent to floor(log2(len + 1)), but not meant to be efficient
		for (var length = len - 1; length >= 0; length = (length / 2) - 1) levels++;
		if (levels == 0) return "";
		var lines = new String[levels];
		for (var i = 0; i < levels; i++) lines[i] = "";
		HeapToStringHelper(data, len, lines, 0, 0, 0);
		for (var i = 0; i < levels; i++) lines[i] += " ";
		HeapToStringHelper(data, len, lines, 1, 0, 0);
		return String.Join("\n", lines);
	}
}

public class PruningRadixTrie
{ // sorry for the indentation, but we need to prevent right-ward shift as much as possible!
private readonly (Node node, int LCP)[] rootPeers = { default };

public int Count = 0;

// The min value of topK at which a Heap-based DEPQ is used instead of an insertion sorted array
public const int DEPQ_THRESHOLD = 125;

private bool isCacheValid = true;

public void WriteTermsToFile(String path)
{
	//save only if terms were changed
	if (isCacheValid) return;
	var terms = GetAllTerms();
	Stopwatch sw = Stopwatch.StartNew();

	try
	{
		using (System.IO.StreamWriter file = new System.IO.StreamWriter(path))
			foreach (var (term, score) in terms)
				file.Write($"{term}\t{score}\n");

		sw.Stop();
		Console.WriteLine(Count.ToString("N0") + " terms written in " + sw.ElapsedMilliseconds.ToString("0,.##") + " seconds.");
		isCacheValid = true;
	}
	catch (Exception e)
	{
		Console.WriteLine("Writing terms exception: " + e.Message);
	}
}

private static void GetAllTerms(List<(String term, score_int score)> results, Node node)
{
	results.Add((node.key, node.score));
	foreach (var peer in node.peers) GetAllTerms(results, peer.node);
}

// We could just use GetTopkTermsForPrefix("", Count), but this should be faster
public List<(String term, score_int score)> GetAllTerms()
{
	var results = new List<(String term, score_int score)>(Count);
	if (Count != 0) GetAllTerms(results, rootPeers[0].node);
	results.Sort((a, b) => b.score.CompareTo(a.score));
	return results;
}

public List<(String term, score_int score)> GetAllTermsUnsorted()
{
	var results = new List<(String term, score_int score)>(Count);
	if (Count != 0) GetAllTerms(results, rootPeers[0].node);
	return results;
}

public List<(String term, score_int score)> GetTopkTermsForPrefix(String prefix, int topK, out score_int prefixScore)
{
	prefixScore = GetScoreForString(prefix);
	return GetTopkTermsForPrefix(prefix, topK);
}

public List<(String term, score_int score)> GetTopkTermsForPrefix(String prefix, int topK)
{
	Node node = rootPeers[0].node;
	var results = new List<(String, score_int)>(Math.Min(topK, Count));

	if (topK <= 0 || node.key == null) return results;
	if (prefix == null) prefix = String.Empty;
	var prefixLength = prefix.Length;
#if COMPRESS_STRINGS
	var prevLCP = 0;
#endif
	if (prefixLength != 0)
	{
#if FORCE_STATIC
		var lcp = prefixLength == 1 ? 1 : 2;

	#if COMPRESS_STRINGS
		if (!skip1.TryGetValue(prefix[0], out node)) return results;
		if (prefixLength > 1)
		{
			var node2 = node;
			if (!skip2.TryGetValue((prefix[0] << 16) | prefix[1], out node)) return results;
			prevLCP = node.peers != node2.peers ? 1 : 0;
		}
	#else
		if (
			prefix.Length == 1
			? !skip1.TryGetValue(prefix[0], out node)
			: !skip2.TryGetValue((prefix[0] << 16) | prefix[1], out node)
		) return results;
	#endif
#else
		var lcp = 0;
#endif

		while (true)
		{
		#if COMPRESS_STRINGS
			var l = Math.Min(prefixLength, prevLCP + node.key.Length);
			while (lcp < l && prefix[lcp] == node.key[lcp - prevLCP]) lcp++;
		#else
			var l = Math.Min(prefixLength, node.key.Length);
			while (lcp < l && prefix[lcp] == node.key[lcp]) lcp++;
		#endif

			if (lcp == prefixLength) break;

			for (int j = 0, peers_Length = node.peers.Length; ; j++)
			{
				if (j == peers_Length) return results;
				if (node.peers[j].LCP == lcp)
				{
					node = node.peers[j].node;
					break;
				}
			}

		#if COMPRESS_STRINGS
			prevLCP = lcp;
		#endif
		}
	}
#if COMPRESS_STRINGS
	var key1 = prefix.Substring(0, prevLCP) + node.key;
#else
	var key1 = node.key;
#endif
	results.Add((key1, node.score));
	if (--topK == 0) return results;

	var i = 0;
	var peers = node.peers;

	for (var peersLength = peers.Length; ; i++)
	{
		if (i == peersLength) return results;
		if (peers[i].LCP >= prefixLength) break;
	}

	node = peers[i].node;
#if COMPRESS_STRINGS
	var key2 = key1.Substring(0, peers[i].LCP) + node.key;
#else
	var key2 = node.key;
#endif

	results.Add((key2, node.score));

	if (--topK == 0) return results;

	// Methinks C# makes a special version of the loop below depending on this value
	var isPriorityQueueJustASortedArray = topK < DEPQ_THRESHOLD - 2;
	// When true, DEPQ is an insertion-sorted array, otherwise its a heap data structure

	// Fun fact: for any given 𝐤, we only need a DEPQ with half the capacity!
	// The reason for that is that at each step, we push two, then pop one,
	// then decrement 𝐤. In other words, 𝐤  decreases at the same rate as the
	// DEPQ increases. Naturally, they will meet in the middle. You still, however,
	// need an extra slot because when they meet in the middle and two get pushed
	// and one gets popped, it's only after the pop that 𝐤  will equal capacity.
	var DEPQ = new AltPtr[topK / 2 + 1];
	var DEPQ_len = 0;
	// This double-ended priority queue

	for (; topK != 0; topK--)
	{
		// Pardon my use of goto's... I needed more control over the control flow
		// than C# would let me without the overhead of function calls in this tight loop.
		// This is why languages need loop labels ...

		var skipSecondItem = false;
		if (node.peers.Length == 0) goto SECOND_ITEM;

		// All elements in node.peers have `LCP >= prefixLength`
		var item = new AltPtr
		{
			peers = node.peers,
			index = 0,
		#if COMPRESS_STRINGS
			key = key2
		#endif
		};

		var score = node.peers[0].node.score;

	LOOP_START:
		// I tried decoupling the full vs not full behavior, and it made it slower for some reason
		// So... this if statement stays here...
		if (DEPQ_len == topK)
		{ // when full, pop the minimum element automatically if we insert
			if (score > DEPQ[0].peers[DEPQ[0].index].node.score) // data[0] is minimum element
			{
				if (isPriorityQueueJustASortedArray)
				{
					var l = 0;
					while (
						l + 1 < DEPQ_len &&
						score > DEPQ[l + 1].peers[DEPQ[l + 1].index].node.score
					) l++;
					for (var k = 0; k < l; k++) DEPQ[k] = DEPQ[k + 1];
					DEPQ[l] = item;
				}
				else BoundedDEPQ<AltPtr>.heapPopMin(DEPQ, DEPQ_len, AltPtr.Comparer, item);
			}
		}
		else
		{
			if (isPriorityQueueJustASortedArray)
			{
				var l = 0;
				while (
					l < DEPQ_len &&
					score > DEPQ[l].peers[DEPQ[l].index].node.score
				) l++;
				for (var k = DEPQ_len; k > l; k--) DEPQ[k] = DEPQ[k - 1];
				DEPQ[l] = item;
			}
			else BoundedDEPQ<AltPtr>.heapifyUp(DEPQ, DEPQ_len, AltPtr.Comparer, item, DEPQ_len);
			DEPQ_len++;
		}

		// This is so the `goto SECOND_ITEM` above doesn't have to run `if (!skipSecondItem)`
		if (skipSecondItem) goto FINISH_ITERATION;

	SECOND_ITEM:
		for (var peersLength = peers.Length; ++i < peersLength;)
		{
			if (peers[i].LCP < prefixLength) continue;
			item = new AltPtr
			{
				peers = peers,
				index = i,
			#if COMPRESS_STRINGS
				key = key1
			#endif
			};
			score = peers[i].node.score;

			// I like the idea of setting i to peersLength better,
			// however that idea was slower on my machine than using a boolean
			skipSecondItem = true;
			goto LOOP_START;
		}

	FINISH_ITERATION:
		if (DEPQ_len == 0) break;

		// pop the maximum element from the DEPQ
		var ptr = DEPQ[--DEPQ_len];

		if (!isPriorityQueueJustASortedArray)
			// when using a heap, the last element is not the maximum, the second element is
			ptr = BoundedDEPQ<AltPtr>.heapPopMax(DEPQ, ref DEPQ_len, AltPtr.Comparer, ptr);

		i = ptr.index;
		peers = ptr.peers;
		node = peers[i].node;

	#if COMPRESS_STRINGS
		key1 = ptr.key;
		key2 = key1.Substring(0, peers[i].LCP) + node.key;
	#else
		key2 = node.key;
	#endif
		results.Add((key2, node.score));
	}

	return results;
}

#if DEBUG_METHODS
private static void checkTrie(HashSet<(Node node, int LCP)[]> encounteredPeers, HashSet<int> diffs, (Node node, int LCP)[] peers, score_int topScore, int minDiff, int maxDiff, ref int nodeCount)
{
	var peersLength = peers.Length;
	for (var i = 0; i < peersLength; i++)
	{
		var peer = peers[i];
		nodeCount -= 1;

		if (peer.LCP < minDiff)
			throw new Exception("Invalid LCP");

		if (peer.LCP > maxDiff)
			throw new Exception("Invalid LCP");

		if (diffs.Contains(peer.LCP))
			throw new Exception("Duplicate diffs");

		diffs.Add(peer.LCP);
	}

	diffs.Clear();

	if (peersLength != 0 && peers[0].node.score > topScore)
		throw new Exception("Invalid sortedness");

	for (var i = 0; ++i < peersLength; )
	{
		if (peers[i].node.score > peers[i - 1].node.score)
			throw new Exception("Invalid sortedness");
	}

	foreach (var (node, LCP) in peers)
	{
		if (node.peers.Length != 0)
		{
			if (encounteredPeers.Contains(node.peers))
			{
				throw new Exception("There's a cycle...." + node.key);
			}

			encounteredPeers.Add(node.peers);
		}
		checkTrie(encounteredPeers, diffs, node.peers, node.score, LCP, node.key.Length, ref nodeCount);
	}
}

public void validateTrie()
{
	var nodeCount = Count;
	var encounteredPeers = new HashSet<(Node node, int LCP)[]>(nodeCount);
	var diffs = new HashSet<int>();

	checkTrie(encounteredPeers, diffs, rootPeers, long.MaxValue, 0, 0, ref nodeCount);
	if (nodeCount != 0)
	{
		throw new Exception("Something got erased");
	}
}

private void assertTreeIsTheSame((Node node, int LCP)[] n1, (Node node, int LCP)[] n2)
{
	var l = n1.Length;
	if (l != n2.Length) throw new Exception("Found a difference!");

	for (var i = 0; i < l; i++)
	{
		var a = n1[i];
		var b = n2[i];
		if (a.LCP != b.LCP || a.node.score != b.node.score || a.node.key != b.node.key)
			throw new Exception("Found a difference!\n\t(" + a.LCP + ", " + a.node.score + ", \"" + a.node.key + "\")\n\t(" + b.LCP + ", " + b.node.score + ", \"" + b.node.key + "\")");
		assertTreeIsTheSame(a.node.peers, b.node.peers);
	}
}

public void assertTreeIsTheSame(PruningRadixTrie other)
{
	assertTreeIsTheSame(rootPeers, other.rootPeers);
}
#endif // DEBUG_METHODS

private static void InsertionSortIndex((Node node, int LCP)[] arr, int index, (Node node, int LCP) e)
{
	for (; index != 0 && e.node.score > arr[index - 1].node.score; index--)
		arr[index] = arr[index - 1];

	for (;index + 1 < arr.Length && e.node.score < arr[index + 1].node.score; index++)
		arr[index] = arr[index + 1];

	arr[index] = e;
}

private static int InsertionSortIndexLeft((Node node, int LCP)[] arr, int index, (Node node, int LCP) e)
{
	for (; index != 0 && e.node.score > arr[index - 1].node.score; index--)
		arr[index] = arr[index - 1];

	arr[index] = e;
	return index;
}

private static int InsertionSortIndexRight((Node node, int LCP)[] arr, int index, (Node node, int LCP) e)
{
	for (;index + 1 < arr.Length && e.node.score < arr[index + 1].node.score; index++)
		arr[index] = arr[index + 1];

	arr[index] = e;
	return index;
}

private static int ImmutableSortedArrayPush(ref (Node node, int LCP)[] arr, (Node node, int LCP) value)
{
	var len = arr.Length;
	var newArray = new (Node node, int LCP)[len + 1];
	Array.Copy(arr, newArray, len);
	arr = newArray;
	return InsertionSortIndexLeft(newArray, len, value);
}

private static void ImmutableArrayRemove<T>(ref T[] arr, int index)
{
	var newArray = new T[arr.Length - 1];
	Array.Copy(arr, newArray, index);
	Array.Copy(arr, index + 1, newArray, index, newArray.Length - index);
	arr = newArray;
}

private static void ExtractSubKNodes(
	ref (Node node, int LCP)[] source,
	int LCP,
	(Node node, int LCP)[] destination,
	ref int destinationCount
)
{
	int sourceLen = source.Length;
	var newNodePeersLen = 0;

	for (int i = 0; i < sourceLen; i++)
	{
		var peer = source[i];
		if (LCP <= peer.LCP) newNodePeersLen++;
		else if (peer.LCP >= 0) destination[destinationCount++] = peer;
	}

	if (newNodePeersLen != sourceLen)
	{
		if (newNodePeersLen == 0) {
			source = Array.Empty<(Node node, int LCP)>();
			return;
		}

		var newNodePeers = new (Node node, int LCP)[newNodePeersLen];

		do
		{
			var peer = source[--sourceLen];
			if (LCP <= peer.LCP)
				newNodePeers[--newNodePeersLen] = peer;
		} while (newNodePeersLen != 0);

		source = newNodePeers;
	}
}

#if FORCE_STATIC
private
#else
public
#endif
bool Delete(String key)
{
	if (key == null || key.Length == 0) return false;
	isCacheValid = false;
	var keyLength = key.Length;
	var grandPeers = default((Node node, int LCP)[]);
	var indexInGrandparent = 0;

	var parentPeers = rootPeers; // the current array in which we're looking
	var indexInParent = 0; // the place we're looking
	var node = parentPeers[indexInParent].node;

	var prevLCP = 0;
	var LCP = 0; // Longest Common Prefix

	if (node.key == null) // Degenerate case: trie is empty
		return false;

	while (true)
	{
		prevLCP = LCP;
		var nodeKeyLength = node.key.Length;

	#if COMPRESS_STRINGS
		nodeKeyLength += prevLCP;
	#endif

		for (
			var l = Math.Min(keyLength, nodeKeyLength);
			LCP < l &&
			#if COMPRESS_STRINGS
				key[LCP] == node.key[LCP - prevLCP];
			#else
				key[LCP] == node.key[LCP];
			#endif
			LCP++
		);

		if (LCP == keyLength && LCP == nodeKeyLength)
			break;

		grandPeers = parentPeers;
		indexInGrandparent = indexInParent;

		// if the score is less than or equal, keep looking for the node that represents `term`
		parentPeers = node.peers;
		indexInParent = findBranch(parentPeers, LCP);

		if (indexInParent < 0) // does not exist in the Trie
			return false;

		node = parentPeers[indexInParent].node;
	}

	// If we broke down here, it means we found a `node` that represents `key`
	Count -= 1;

	var nodesToPush = node.peers; // All these nodes need to be placed back in the trie
	if (nodesToPush.Length == 0)
	{ // there's nothing to be placed back in the trie, just delete
		if (parentPeers == rootPeers)
			rootPeers[0] = default;
		else
			ImmutableArrayRemove(ref grandPeers[indexInGrandparent].node.peers, indexInParent);

		return true;
	}

	var promotedNode = nodesToPush[0].node;
#if COMPRESS_STRINGS
	promotedNode = new Node(node.key.Substring(0, nodesToPush[0].LCP - prevLCP) + promotedNode.key, promotedNode.score, promotedNode.peers);
#endif
	indexInParent = InsertionSortIndexRight(parentPeers, indexInParent, (promotedNode, prevLCP));

	// nodesToPush is now the queue of nodes to insert into the tree, but we skip the first index
	if (nodesToPush.Length > 1)
		PushNodes(
			nodesToPush
			, (nodesToPush[0].LCP, new AltPtr2 { peers = parentPeers, index = indexInParent })
			, 1
		#if COMPRESS_STRINGS
			, node.key
			, prevLCP
		#endif
		);

	return true;
}

private score_int GetScoreForString(String key)
{
	if (key == null || key.Length == 0) return 0;
	var keyLength = key.Length;

	var parentPeers = rootPeers; // the current array in which we're looking
	var indexInParent = 0; // the place we're looking
	var node = parentPeers[indexInParent].node;

	var LCP = 0; // Longest Common Prefix

	if (node.key == null) // Degenerate case: trie is empty
		return 0;

	while (true)
	{
		var prevLCP = LCP;
		var nodeKeyLength = node.key.Length;

	#if COMPRESS_STRINGS
		nodeKeyLength += prevLCP;
	#endif

		for (
			var l = Math.Min(keyLength, nodeKeyLength);
			LCP < l &&
			#if COMPRESS_STRINGS
				key[LCP] == node.key[LCP - prevLCP];
			#else
				key[LCP] == node.key[LCP];
			#endif
			LCP++
		);

		if (LCP == keyLength && LCP == nodeKeyLength)
			return node.score;

		// if the score is less than or equal, keep looking for the node that represents `term`
		parentPeers = node.peers;
		indexInParent = findBranch(parentPeers, LCP);

		if (indexInParent < 0) // does not exist in the Trie
			return 0;

		node = parentPeers[indexInParent].node;
	}
}

#if FORCE_STATIC
private
#else
public
#endif
void AddTerm(String term, score_int score)
{
	var newScore = unchecked((System.UInt64)GetScoreForString(term) + (System.UInt64)score);
	Set(term, unchecked((long)Math.Min(newScore, score_int.MaxValue)));
}

#if FORCE_STATIC
private
#else
public
#endif
void Set(String term, score_int score)
{
	if (term == null || term.Length == 0) return;
	isCacheValid = false;
	var termLength = term.Length;

	var parentPeers = rootPeers; // the current array in which we're looking
	var indexInParent = 0; // the place we're looking
	var prevLCP = 0;
	var LCP = 0; // Longest Common Prefix
	var node = parentPeers[indexInParent].node;

	if (node.key == null) // Degenerate case: trie is empty
	{
		parentPeers[indexInParent].node = new Node(term, score);
		Count = 1;
		return;
	}

	// loop through to find the position where Node(term, score) should be placed
	// this might be dictated solely by score if it happens to be the highest score
	// of its prefix. Otherwise stop when we find `term` in the trie or if we get
	// to a leaf

	while (true)
	{
		prevLCP = LCP;
		var nodeKeyLength = node.key.Length;

	#if COMPRESS_STRINGS
		nodeKeyLength += prevLCP;
	#endif

		for (
			var l = Math.Min(termLength, nodeKeyLength);
			LCP < l &&
			#if COMPRESS_STRINGS
				term[LCP] == node.key[LCP - prevLCP];
			#else
				term[LCP] == node.key[LCP];
			#endif
			LCP++
		);

		if (LCP == termLength && LCP == nodeKeyLength)
			break;

		if (score > node.score)
		{	// if score is higher than the observed node's, insert new Node in its place
			// and then traverse `node` to find the peers for new Node
			var newPeers = new (Node node, int LCP)[termLength + 1 - prevLCP]; // maximum possible capacity

			var newPeersCount = GetPeers(newPeers, node, LCP, term, LCP == prevLCP);

			if (newPeersCount != newPeers.Length)
				Array.Resize(ref newPeers, newPeersCount);

		#if COMPRESS_STRINGS
			term = term.Substring(prevLCP);
		#endif

			InsertionSortIndexLeft(
				parentPeers,
				indexInParent,
				(new Node(term, score, newPeers), prevLCP)
			);

			return;
		}

		// if the score is less than or equal, keep looking for the node that represents `term`
		var index = findBranch(node.peers, LCP);

		if (index < 0)
		{	// Found a leaf! This Node has a unique LCP! Just add it to the list!
			Count += 1;

		#if COMPRESS_STRINGS
			term = term.Substring(prevLCP);
		#endif

			ImmutableSortedArrayPush(ref parentPeers[indexInParent].node.peers, (new Node(term, score), LCP));
			return;
		}

		indexInParent = index;
		parentPeers = node.peers;
		node = parentPeers[indexInParent].node;
	}

	// If we broke down here, it means we found a `node` that represents `term`
	var nodesToPush = node.peers;
	var nodesToPushLength = nodesToPush.Length;
	if (nodesToPushLength == 0 || score >= nodesToPush[0].node.score)
	{ // score change doesn't affect sortedness with children: just update in-place
		InsertionSortIndex(parentPeers, indexInParent, (new Node(node.key, score, nodesToPush), prevLCP));
		return;
	}

	LCP = nodesToPush[0].LCP;

	// promote nodesToPush[0] because it has a higher score than the one being inserted
	indexInParent = InsertionSortIndexRight(parentPeers, indexInParent, (nodesToPush[0].node, prevLCP));

	// This overwrites nodesToPush[0] with the new Node and sorts
#if COMPRESS_STRINGS
	term = String.Empty;
#endif
	InsertionSortIndexRight(nodesToPush, 0, (new Node(term, score), termLength));
	// nodesToPush is now the queue of nodes to insert into the tree

	PushNodes(
		nodesToPush
		, (LCP, new AltPtr2 { peers = parentPeers, index = indexInParent })
		, 0
	#if COMPRESS_STRINGS
		, node.key
		, prevLCP
	#endif
	);
}

private static void PushNodes(
	(Node node, int LCP)[] queue
	, (int LCP, AltPtr2 ptr) firstMaximum
	, int indexInQueue
#if COMPRESS_STRINGS
	, String deletedKey
	, int originalLCP
#endif
)
{
	// Precomputes the localMaximums table size
	var localMaximumsLastIndex = 0;
	var maxLCP = firstMaximum.LCP;
	var queueLength = queue.Length;

	for (int j = indexInQueue, len = queueLength - 1; j < len; j++) // don't check last value because it can't be the local Maximum for any subsequent node
	{
		var lcp = queue[j].LCP;
		if (lcp > maxLCP)
		{
			maxLCP = lcp;
			localMaximumsLastIndex += 1;
		}
	}

	// Keeps a list of each new runningMaximum
	var localMaximums = new (int LCP, AltPtr2 ptr)[localMaximumsLastIndex + 1];
	// Idea: we could precompute the final size of these localMaximums and do fewer intermediate "allocations"
	localMaximums[0] = firstMaximum;
	localMaximumsLastIndex = 0;

	// Iterate through nodesToPush, and insert each into the first node in localMaximums with a greater LCP than it
	maxLCP = firstMaximum.LCP;

	while (true)
	{
		var node = queue[indexInQueue].node;
		var LCP = queue[indexInQueue].LCP;

		if (LCP >= maxLCP)
		{
			var parentPeers = localMaximums[localMaximumsLastIndex].ptr.peers;
			var indexInParent = localMaximums[localMaximumsLastIndex].ptr.index;

			while (true) // find place where score fits in horizontal traversal
			{
				var grandPeers = parentPeers;
				var indexInGrand = indexInParent;
				parentPeers = grandPeers[indexInGrand].node.peers;
				indexInParent = findBranch(parentPeers, maxLCP);

				if (indexInParent < 0)
				{
				#if COMPRESS_STRINGS
					node = new Node(deletedKey.Substring(maxLCP - originalLCP, LCP - maxLCP) + node.key, node.score, node.peers);
				#endif
					indexInParent = ImmutableSortedArrayPush(ref parentPeers, (node, maxLCP));
					grandPeers[indexInGrand].node.peers = parentPeers;
					break;
				}

				if (node.score >= parentPeers[indexInParent].node.score)
				{
					// `node` originally had a higher LCP, therefore we can guarantee there will be no collision here
					ImmutableSortedArrayPush(
						ref node.peers,
						parentPeers[indexInParent]
					);

				#if INVARIANT_CHECKS
					// It's impossible to corrupt any localMaximums pointers because `parentPeers`
					// is the deepest layer ever encountered
					foreach (var (lcp, ptr) in localMaximums)
						if (ptr.peers == parentPeers) throw new Exception("Well this wasn't supposed to happen!");
				#endif


				#if COMPRESS_STRINGS
					node = new Node(deletedKey.Substring(maxLCP - originalLCP, LCP - maxLCP) + node.key, node.score, node.peers);
				#endif
					indexInParent = InsertionSortIndexLeft(parentPeers, indexInParent, (node, maxLCP));
					break;
				}
			}

			if (++indexInQueue == queueLength) break;

			if (LCP > maxLCP)
			{	// LCP is a new localMaximum!
				localMaximumsLastIndex += 1;
				localMaximums[localMaximumsLastIndex] = (LCP, new AltPtr2 { peers = parentPeers, index = indexInParent });
				maxLCP = LCP;
			}
		}
		else
		{
			// When the LCP of this node is lower than the maximum LCP,
			// Find the first localMaximum which is higher than LCP
			// Let newLCP become LCP

			int localMaximumsIndex = 0; // use this as the left-bound in the binary search
			int right = localMaximumsLastIndex - 1; // we already checked localMaximumsLastIndex

			if (right >= 0 && LCP > localMaximums[right].LCP) // optimization: most of the time, the last localMaximum has the first LCP greater than the current LCP
			{
				localMaximumsIndex = localMaximumsLastIndex;
			}
			else
			{ // fallback on binary search
				right -= 1; // we already checked localMaximumsLastIndex - 1
				while (localMaximumsIndex <= right)
				{
					int mid = unchecked((int)(((uint)localMaximumsIndex + (uint)right) >> 1)); // divides by two regardless of overflow

					if (LCP < localMaximums[mid].LCP)
						right = mid - 1;
					else
						localMaximumsIndex = mid + 1;
				}
			}

			// `localMaximumsIndex` is the first position for which LCP < localMaximums[pos].LCP
			var grandPeers = localMaximums[localMaximumsIndex].ptr.peers;
			var indexInGrand = localMaximums[localMaximumsIndex].ptr.index;
			var parentPeers = grandPeers[indexInGrand].node.peers;

			// If `localMaximums[localMaximumsIndex + 1]` holds a reference to the old `parentPeers`, it needs to be updated with the new `parentPeers`.
			// `nextMaximum` is the index to overwrite to update the peers array pointer, else 0
			var nextMaximum = localMaximumsIndex + 1;
			if (localMaximumsIndex >= localMaximumsLastIndex || parentPeers != localMaximums[nextMaximum].ptr.peers)
				nextMaximum = 0;

		#if INVARIANT_CHECKS
			// It's impossible to invalidate any pointers besides `nextMaximum` because the runningMaximums list are, by construction, a chain of nodes where the each one is a descendant of the previous in the runningMaximums list. Pointer invalidation occurs when the next node is a direct child of the previous, rather than just an arbitrarily deep descendant.
			for (var j = nextMaximum; ++j <= localMaximumsLastIndex;)
				if (parentPeers == localMaximums[j].ptr.peers)
					throw new Exception("This isn't supposed to happen!");
		#endif

			// the LCP between two nodes is the minimum of the two (when in relation to the same parent)
			// therefore, since LCP is less than localMaximums[localMaximumsIndex].LCP, LCP is
			// the new branch point. LCP is guaranteed to not be present in parentPeers
			var indexInParent = ImmutableSortedArrayPush(ref parentPeers, (node, LCP));

			// Update all the old parentPeers pointers
			grandPeers[indexInGrand].node.peers = parentPeers;
			if (nextMaximum != 0)
			{
			#if INVARIANT_CHECKS
				// ptr.index is impossible to invalidate by inserting `node` into `parentPeers` because the queue is sorted, i.e. node.score <= ptr.score
				if (indexInParent <= localMaximums[nextMaximum].ptr.index)
					throw new Exception("This isn't supposed to happen");
			#endif
				localMaximums[nextMaximum].ptr.peers = parentPeers;
			}

			if (++indexInQueue == queueLength) break;
		}
	}
}

private static int findBranch((Node node, int LCP)[] peers, int LCP)
{
	for (int i = 0, len = peers.Length; i < len; i++)
		if (LCP == peers[i].LCP) return i;

	return -1;
}

// Fill newPeers with the peers intended for `term`
// If a node representing `term` is found somewhere in the trie, delete it
private int GetPeers((Node node, int LCP)[] newPeers, Node node, int LCP, String term, bool nodeMatchesTheSameAsPrevious)
{
	// if (LCP == termLen && LCP == node.key.Length) <- This is impossible
	var newPeersCount = 1;

	// Add `node` to newPeers, and its peers with diffs less than LCP
	// This is guaranteed to be in sorted order
	if (!nodeMatchesTheSameAsPrevious)
		ExtractSubKNodes(ref node.peers, LCP, newPeers, ref newPeersCount);

	// This code inserts `node` after dealing with `node.peers` so that
	// the `node.peers` pointer doesn't need to be written twice
	newPeers[0] = (node, LCP);
	(Node node, int LCP)[] grandPeers = newPeers;
	int indexInGrand = 0;
	var termLength = term.Length;
	var nodeKeyLength = node.key.Length;
#if COMPRESS_STRINGS
	nodeKeyLength += LCP;
#endif
	// We track this in case we have to modify grandparentPeers[index].node.peers

	// find all peers with LCP in (LCP, termLength]
	while (LCP != termLength)
	{
		while (true) // find next node with one more character in common with `term`
		{
			var parentPeers = grandPeers[indexInGrand].node.peers;
			var indexInParent = findBranch(parentPeers, LCP);

			// if we reached then end of this horizontal line, terminate
			if (indexInParent < 0)
			{
				Count += 1;
				return newPeersCount;
			}

			node = parentPeers[indexInParent].node;

			if (LCP != node.key.Length &&
			#if COMPRESS_STRINGS
				term[LCP] == node.key[0]
			#else
				term[LCP] == node.key[LCP]
			#endif
			)
			{
				SupplantNodeFromParentWithNextBranchingNode(
					grandPeers,
					indexInGrand,
					indexInParent,
					node.peers,
					LCP
				);
				break;
			}

			grandPeers = parentPeers;
			indexInGrand = indexInParent;
		}

		nodeKeyLength = node.key.Length;
	#if COMPRESS_STRINGS
		var startLCP = LCP;
		nodeKeyLength += startLCP;
	#else
		var startLCP = 0;
	#endif
		var len = Math.Min(termLength, nodeKeyLength);
		do LCP++;
		while (LCP < len && term[LCP] == node.key[LCP - startLCP]);

		if (LCP != termLength || LCP != nodeKeyLength)
		{ // if the characters `term` does not exactly match node
			var extractIndex = newPeersCount;
			newPeersCount += 1;
			ExtractSubKNodes(ref node.peers, LCP, newPeers, ref newPeersCount);
		#if COMPRESS_STRINGS
			node = new Node(node.key.Substring(LCP - startLCP), node.score, node.peers);
		#endif
			newPeers[extractIndex] = (node, LCP);
			grandPeers = newPeers;
			indexInGrand = UnboundedInsertionSortElementsLeft(newPeersCount, newPeers, extractIndex);
		}
	}

	// LCP now equals termLength

	// if `node` doesn't represent `term` at this point, go look for the right `node`
	if (LCP != nodeKeyLength)
	{
		while (true)
		{
			var parentPeers = grandPeers[indexInGrand].node.peers;
			var indexInParent = findBranch(parentPeers, LCP);

			// if we reached then end of this horizontal line, terminate
			if (indexInParent < 0)
			{
				Count += 1;
				return newPeersCount;
			}

			node = parentPeers[indexInParent].node;

		#if COMPRESS_STRINGS
			if (0 == node.key.Length)
		#else
			if (LCP == node.key.Length)
		#endif
			{
				SupplantNodeFromParentWithNextBranchingNode(
					grandPeers,
					indexInGrand,
					indexInParent,
					node.peers,
					LCP
				);
				break;
			}
			grandPeers = parentPeers;
			indexInGrand = indexInParent;
		}
	}

	// node.key represents term

	{
		// Move all peers (that aren't marked for death) from node.peers to newPeers
		var place = newPeersCount;
		foreach (var peer in node.peers)
			if (peer.LCP >= 0) newPeers[newPeersCount++] = peer;

		if (place < newPeersCount)
			UnboundedInsertionSortElementsLeft(newPeersCount, newPeers, place);
	}

	// `node` is the Node that represents `term`, so we can throw it away now
	return newPeersCount;
}

static int UnboundedInsertionSortElementsLeft(int newPeersCount, (Node node, int LCP)[] newPeers, int place)
{
	int finalIndexOfFirstElement = place;

	do
	{
		var index = place;
		var element = newPeers[index];

		// Once the first element is found which does not need sorting, we can stop
		if (element.node.score <= newPeers[index - 1].node.score)
			break;

		do
		{
			newPeers[index] = newPeers[index - 1];
			index -= 1;
		} while (element.node.score > newPeers[index - 1].node.score);
		newPeers[index] = element;

		// grabs index to return, on first iteration only
		if (finalIndexOfFirstElement == place)
			finalIndexOfFirstElement = index;
	} while (++place < newPeersCount);

	return finalIndexOfFirstElement;
}

private static void SupplantNodeFromParentWithNextBranchingNode(
	(Node node, int LCP)[] grandparentPeers,
	int indexInGrandparent,
	int indexInParent,
	(Node node, int LCP)[] nodePeers,
	int LCP
)
{
	// find next link in the horizontal linked list
	var oldIndex = findBranch(nodePeers, LCP);

	if (oldIndex < 0) // if there is no next link, just remove node's old spot
		ImmutableArrayRemove(ref grandparentPeers[indexInGrandparent].node.peers, indexInParent);
	else
	{
		// move next link into node's old spot and sort
		InsertionSortIndexRight(grandparentPeers[indexInGrandparent].node.peers, indexInParent, nodePeers[oldIndex]);
		// mark its former slot for death
		nodePeers[oldIndex].LCP = -1;
		// this is an optimization so that nodePeers is reallocated fewer times
	}
}


#if FORCE_STATIC
private
#else
public
#endif
void AddTerms(List<(String term, score_int score)> terms)
{
	var count = terms.Count;
	if (count == 0) return;

#if !FORCE_STATIC
	if (Count != 0)
	{
		// Optimization idea: Depending on how large `terms` is and how small the structure is,
		// it might be faster to just nuke the previous structure and do the equivalent of
		// `GetAllTermsUnsorted` to add all terms to a Dictionary<String, score_int>, then
		// combine the scores with the ones in `terms`, convert the Dictionary to a sorted list,
		// and rebuild the structure from scratch. It's not that `AddTerm` is slow per se, but that
		// generating a structure from a sorted deduplicated list is 𝐯𝐞𝐫𝐲 fast.
		foreach (var (term, score) in terms) AddTerm(term, score);
		return;
	}
#endif

	{
		var map = new Dictionary<String, score_int>(count);
		var prevScore = score_int.MaxValue;
		var i = 0;
		do
		{
			var term = terms[i].term;
			var score = terms[i].score;
			var needsDeduplicating = map.TryGetValue(term, out var old_score);
			var needsSorting = score > prevScore;

			if (needsDeduplicating || needsSorting)
			{
				isCacheValid = false;
				if (needsDeduplicating)
					map[term] = score + old_score;

				for (var j = i; ++j < count; )
				{
					var term2 = terms[j].term;
					var score2 = terms[j].score;

					if (map.TryGetValue(term2, out var old_score2))
					{
						map[term2] = score2 + old_score2;
						needsDeduplicating = true;
					}
					else map.Add(term2, score2);
				}

				if (needsDeduplicating)
				{
					count = map.Count;
					terms.Clear();
					foreach (var pair in map) terms.Add((pair.Key, pair.Value));
				}
				terms.Sort((a, b) => b.score.CompareTo(a.score));
				break;
			}

			map.Add(term, score);
			prevScore = score;
		} while (++i < count);
	}

	this.rootPeers[0] = (new Node(terms[0].term, terms[0].score), 0);

	for (var allTermIndex = 0; ++allTermIndex < count;)
	{
		var (term, score) = terms[allTermIndex];
		var termLength = term.Length;
		var lcp = 0;
		var parent = this.rootPeers;
		var positionInParent = 0;

	FIND_TERM_LOCATION:
		var node = parent[positionInParent].node;

		for (
		#if COMPRESS_STRINGS
			int c = lcp,
		#else
			int c = 0,
		#endif
			len = Math.Min(termLength, c + node.key.Length);
			lcp < len && term[lcp] == node.key[lcp - c];
			lcp++
		) ;

		var oldLength = node.peers.Length;
		for (var j = 0; j < oldLength; j++)
		{
			if (lcp == node.peers[j].LCP)
			{
				parent = node.peers;
				positionInParent = j;
				goto FIND_TERM_LOCATION;
			}
		}

#if COMPRESS_STRINGS
	#if FORCE_STATIC
		term = String.Intern(term.Substring(lcp));
	#else
		term = term.Substring(lcp);
	#endif
#endif

		// this is fast in C#
		var newPeers = new (Node, int)[oldLength + 1];
		newPeers[oldLength] = (new Node(term, score), lcp);

		while (--oldLength >= 0) // copy to new array
			newPeers[oldLength] = node.peers[oldLength];

		// Write newPeers into node
		node.peers = newPeers;

		// Because we're dealing with structs, we have to write our node back to its peers array after we change the node's peers pointer
		parent[positionInParent].node = node;
	}

	this.Count = count;
#if FORCE_STATIC
	FillDictionaryStructure();
#endif
}

public bool ReadTermsFromFile(String path)
{
#if FORCE_STATIC
	if (Count != 0)
		throw new Exception("Cannot read terms into an already initialized static PruningRadixTrie");
#endif
	if (!System.IO.File.Exists(path))
	{
		Console.WriteLine("Could not find file " + path);
		return false;
	}
	Console.WriteLine("Instantiating Trie ...");
	Stopwatch sw = Stopwatch.StartNew();
	var terms = new List<(String term, score_int score)>();
	try
	{
		using (System.IO.Stream corpusStream = System.IO.File.OpenRead(path))
			using (System.IO.StreamReader sr = new System.IO.StreamReader(corpusStream, System.Text.Encoding.UTF8, false))
				while (true)
				{
					String line = sr.ReadLine();
					if (line == null) break;

					var numberStart = 1 + line.IndexOf('\t');
					var term = line.Substring(0, numberStart - 1);
					var dataStart = line.IndexOf('\t', numberStart + 1);
					var score = line.Substring(numberStart, (dataStart < 0 ? line.Length : dataStart) - numberStart);
					var termData = dataStart < 0 ? null : line.Substring(dataStart + 1);
					terms.Add((term, score_int.Parse(score)));
				}
	}
	catch (Exception e)
	{
		Console.WriteLine("Loading terms exception: " + e.Message);
	}

	sw.Stop();
	Console.WriteLine("\tRead term list in " + sw.ElapsedMilliseconds.ToString("0,.##") + " seconds. (" + terms.Count.ToString("N0") + " terms)");
	sw.Restart();
	AddTerms(terms);
	sw.Stop();
	Console.WriteLine(
		"\tMade structure in " + sw.ElapsedMilliseconds.ToString("0,.##") + " seconds."
	);

	return true;
}

#if FORCE_STATIC
// Skip the first character
Dictionary<Char, Node> skip1 = new Dictionary<Char, Node>();
// Skip the first two characters
Dictionary<Int32, Node> skip2 = new Dictionary<Int32, Node>();

private void FillDictionaryStructure()
{
	var node = rootPeers[0].node;

	// Skip the first two characters
	do
	{
		skip1[node.key[0]] = node;
		if (node.key.Length > 1)
			skip2[(node.key[0] << 16) | node.key[1]] = node;

		var peerNode = default(Node);
		for (int i = 0, len = node.peers.Length; i < len; i++)
		{
			var firstChar = node.key[0] << 16;
			var peer = node.peers[i];

			if (peer.LCP == 0)
			{
				peerNode = peer.node;
			}
			else if (peer.LCP == 1)
			{
		NEXT_PAIR:

		#if COMPRESS_STRINGS
			if (peer.node.key.Length > 0)
				skip2[firstChar | peer.node.key[0]] = peer.node;
		#else
			if (peer.node.key.Length > 1)
				skip2[firstChar | peer.node.key[1]] = peer.node;
		#endif

				foreach (var peer2 in peer.node.peers)
				{
					if (peer2.LCP == 1)
					{
						peer = peer2;
						goto NEXT_PAIR;
					}
				}
			}
		}
		node = peerNode;
	} while (node.peers != null);
}
#endif
}
}
