interface DynSDTNode {
	key: string
	score: number
	branch_points: Array<BranchPoint>
}

interface BranchPoint {
	LCP: number
	node: DynSDTNode
};

interface DynSDT_Ptr {
	LCP: number
	bp: Array<BranchPoint>
	i: number
}

interface DynSDT_HeapPtr {
	bp: Array<BranchPoint>
	i: number
}

export class DynSDT {
	public root_ranch_points: [BranchPoint] | [{ LCP: number; node: null }] = [{ LCP: 0, node: null }]

	get root() {
		return this.root_ranch_points[0].node
	}

	set root(root) {
		this.root_ranch_points[0].node = root
	}

	private InsertionSortIndexUp2(Q: Array<DynSDT_HeapPtr>, j: number) {
		const e = Q[j]
		for (; j !== 0 && e.bp[e.i].node.score > Q[j - 1].bp[Q[j - 1].i].node.score; j--)
			Q[j] = Q[j - 1];

		Q[j] = e;
		return j;
	}

	TopCompletions(p: string, k: number) {
		const c = new Array<string>()
		if (!(k > 0)) return c
		const L = this.FindLocusForPrefix(p)
		if (!L) return c
		c.push(L.key)
		if (--k === 0) return c

		let bp = L.branch_points
		let i = 0
		for (; ; ++i) {
			if (i === bp.length) return c
			if (bp[i].LCP >= p.length) break
		}
		c.push(bp[i].node.key)

		const Q = new Array<DynSDT_HeapPtr>()

		while (--k > 0) {
			if (bp[i].node.branch_points.length > 0) {
				let j = Q.push({ bp: bp[i].node.branch_points, i: 0 }) - 1
				const e = Q[j]
				const s = e.bp[e.i].node.score
				while (--j >= 0 && s < Q[j].bp[Q[j].i].node.score)
					Q[j + 1] = Q[j];
				Q[j + 1] = e;
			}

			while (++i < bp.length) {
				if (bp[i].LCP >= p.length) {
					let j = Q.push({ bp, i }) - 1
					const e = Q[j]
					const s = e.bp[e.i].node.score
					while (--j >= 0 && s < Q[j].bp[Q[j].i].node.score)
						Q[j + 1] = Q[j];
					Q[j + 1] = e;
					break
				}
			}

			if (Q.length === 0) return c;
			({ bp, i } = Q.pop()!);
			c.push(bp[i].node.key)
		}

		return c
		/*
		L ← FindLocusForPrefix(T, p) orelse return
		AppendToList(c, L.key)
		if --k ⩵ 0 then return
		bp ← L.branch-points // the current list of branch points
		i ← 0 // the current index in bp (0-indexed)
		while (i < |bp| or return) and bp[i].LCP < |p| do ++i // find first bp[i] with LCP ≥ |p|
		AppendToList(c, bp[i].node.key)
		Q ← new DEPQ of capacity k // When full, HeapPush internally calls HeapPopMin to constrain size to k
		while --k > 0 do
			if |bp[i].node.branch-points| > 0 then
				HeapPush(Q, { bp: bp[i].node.branch-points, i: 0 }) // horizontal candidate
			while ++i < |bp| do
				if bp[i].LCP ≥ |p| then // this check is always true when bp ≠ L.branch-points
					HeapPush(Q, { bp, i }) // vertical candidate
					break
			if |Q| ⩵ 0 then return
			bp, i ← HeapPopMax(Q) // The size of Q is now constrained to the new value of k
			AppendToList(c, bp[i].node.key)
		*/
	}

	Set(term: string, score: number) {
		// console.log(term, score)
		if (!this.root) {
			this.root = { key: term, score, branch_points: [] }
			return
		}

		let bp = this.root_ranch_points as Array<BranchPoint>
		let i = 0
		let n = this.root
		let lcp = 0

		while (true) {
			for (
				const min = Math.min(term.length, n.key.length);
				lcp < min && term[lcp] === n.key[lcp];
				lcp++
			);

			if (lcp === term.length && lcp === n.key.length) {
				this.Set_ExactMatchFound(score, n, bp, i)
				return
			}

			if (score > n.score) {
				this.Set_ScoreLocationFound(term, score, lcp, bp, i)
				return
			}

			bp = n.branch_points
			const ret = this.FindNodeForLCP(bp, lcp)
			if (!ret[0]) {
				bp.push({ LCP: lcp, node: { key: term, score, branch_points: [] } })
				return
			}
			[n, i] = ret
		}
	}

	private Set_ExactMatchFound(score: number, n: DynSDTNode, bp: BranchPoint[], i: number) {
		n.score = score
		const Q = n.branch_points
		if (Q.length === 0 || score >= Q[0].node.score) {
			this.InsertionSortIndex(bp, i)
			return
		}

		const R = new Array<DynSDT_Ptr>()
		bp[i].node = Q[0].node
		i = this.InsertionSortIndexDown(bp, i)
		R.push({ LCP: Q[0].LCP, bp, i })
		Q[0] = { LCP: n.key.length, node: { key: n.key, score, branch_points: [] } }
		this.InsertionSortIndexDown(Q, 0)

		for (const branch_point of Q) {
			const { LCP, node } = branch_point
			let { LCP: max_LCP, bp, i } = R[R.length - 1]
			if (LCP >= max_LCP) {
				while (true) {
					bp = bp[i].node.branch_points
					const ret = this.FindNodeForLCP(bp, max_LCP)

					if (!ret[0]) {
						branch_point.LCP = max_LCP
						i = this.InsertionSortIntoList(bp, branch_point)
						break
					}

					[n, i] = ret

					if (node.score >= n.score) {
						this.InsertionSortIntoList(node.branch_points, bp[i])
						branch_point.LCP = max_LCP
						bp[i] = branch_point
						i = this.InsertionSortIndexUp(bp, i)
						break
					}
				}

				if (LCP > max_LCP && node !== Q[Q.length - 1].node) {
					R.push({ LCP, bp, i })
				}
			}
			else {
				let l = 0
				let r = R.length - 2
				while (l <= r) {
					const m = l + Math.floor((r - l) / 2)
					if (LCP < R[m].LCP)
						r = m - 1
					else
						l = m + 1
				}
				({ bp, i } = R[l])
				this.InsertionSortIntoList(bp[i].node.branch_points, branch_point)
			}
		}
	}

	private InsertionSortIntoList(bp: BranchPoint[], n: BranchPoint) {
		return this.InsertionSortIndexUp(bp, bp.push(n) - 1)
	}

	private FindLocusForPrefix(p: string) {
		let n = this.root // the current node
		let lcp = 0
		while (n !== null) {
			for ( // compute LCP
				const min = Math.min(p.length, n.key.length);
				lcp < min && p[lcp] === n.key[lcp];
				++lcp
			);
			if (lcp === p.length) break
			[n] = this.FindNodeForLCP(n.branch_points, lcp)
		}
		return n
	}

	private FindNodeForLCP(bp: BranchPoint[], lcp: number): [DynSDTNode | null, number] {
		for (let i = 0; i < bp.length; i++) {
			if (bp[i].LCP === lcp)
				return [bp[i].node, i]
		}
		return [null, NaN]
	}

	private Set_ScoreLocationFound(term: string, score: number, LCP: number, bp: BranchPoint[], i: number) {
		const BP = new Array<BranchPoint>()
		let n = bp[i].node
		BP.push({ LCP, node: n })
		bp[i].node = { key: term, score, branch_points: BP }
		i = this.InsertionSortIndexUp(bp, i)
		n.branch_points = this.ExtractLCPsBelowThreshold(n.branch_points, LCP, BP)
		bp = BP
		i = 0

		while (LCP !== term.length) {
			do {
				bp = bp[i].node.branch_points
				const ret = this.FindNodeForLCP(bp, LCP)
				if (!ret[0]) return
				[n, i] = ret
			} while (LCP === n.key.length || term[LCP] !== n.key[LCP])
			const branch_point = bp[i]
			this.SupplantNodeFromParent(bp, i, n, LCP)
			for (const min = Math.min(term.length, n.key.length); ++LCP < min && term[LCP] == n.key[LCP];);
			if (LCP !== term.length || LCP !== n.key.length) {
				const j = BP.length
				branch_point.LCP = LCP
				BP.push(branch_point)
				n.branch_points = this.ExtractLCPsBelowThreshold(n.branch_points, LCP, BP)
				i = this.Merge2SortedSubarrays(BP, j)
				bp = BP;
			}
		}

		if (LCP != n.key.length) {
			do {
				bp = bp[i].node.branch_points
				const ret = this.FindNodeForLCP(bp, LCP)
				if (!ret[0]) return
				[n, i] = ret
			} while (LCP != n.key.length)
			this.SupplantNodeFromParent(bp, i, n, LCP)
		}

		const j = BP.length
		Array.prototype.push.apply(BP, n.branch_points)
		this.Merge2SortedSubarrays(BP, j)
	}

	private Merge2SortedSubarrays(bp: BranchPoint[], i: number) {
		let finalIndexOfFirstElement = i;

		do {
			var index = i;
			var element = bp[index];

			// Once the first element is found which does not need sorting, we can stop
			if (element.node.score <= bp[index - 1].node.score)
				break;

			do { // insertion sort one element
				bp[index] = bp[index - 1];
				index -= 1;
			} while (element.node.score > bp[index - 1].node.score);
			bp[index] = element;

			// grabs index to return, on first iteration only
			if (finalIndexOfFirstElement == i)
				finalIndexOfFirstElement = index;
		} while (++i < bp.length);

		return finalIndexOfFirstElement;
	}

	private SupplantNodeFromParent(bp: BranchPoint[], i: number, n: DynSDTNode, LCP: number) {
		const [c, j] = this.FindNodeForLCP(n.branch_points, LCP)
		if (c === null) {
			bp.splice(i, 1)
			return
		}
		bp[i] = n.branch_points[j]
		this.InsertionSortIndexDown(bp, i)
		n.branch_points.splice(j, 1)
	}

	private ExtractLCPsBelowThreshold(src: Array<BranchPoint>, lcp: number, dst: Array<BranchPoint>) {
		const L = new Array<BranchPoint>()
		for (const branch_point of src)
			(lcp > branch_point.LCP ? dst : L).push(branch_point)
		return L
	}


	private InsertionSortIndex(bp: BranchPoint[], i: number) {
		const e = bp[i]
		for (; i !== 0 && e.node.score > bp[i - 1].node.score; i--)
			bp[i] = bp[i - 1];

		for (; i + 1 < bp.length && e.node.score < bp[i + 1].node.score; i++)
			bp[i] = bp[i + 1];

		bp[i] = e;
	}

	private InsertionSortIndexUp(bp: BranchPoint[], i: number) {
		const e = bp[i]
		for (; i !== 0 && e.node.score > bp[i - 1].node.score; i--)
			bp[i] = bp[i - 1];

		bp[i] = e;
		return i;
	}

	private InsertionSortIndexDown(bp: BranchPoint[], i: number) {
		const e = bp[i]
		for (; i + 1 < bp.length && e.node.score < bp[i + 1].node.score; i++)
			bp[i] = bp[i + 1];

		bp[i] = e;
		return i;
	}
}
