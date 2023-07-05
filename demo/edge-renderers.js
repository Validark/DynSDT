const MAX_STATE = 47
function getStateFromURL() {
	return Math.min(MAX_STATE, parseInt(window.location.href.split("#").pop()) || 0)
}

const START_STATE = getStateFromURL()

const REMOVE_DIALOG = false
let WAIT_TIME = 0

// Don't look at this code. It is not polished or maintainable... hahaha

let decomposed_id = 0;
{
	function reverseDecompose(str)
	{
		if ("wikipedia$".startsWith(str))
			return "wikipedia$"
		if ("list$".startsWith(str))
			return "list$"
		if ("list of$".startsWith(str))
			return "list of$"
		if ("of$".startsWith(str))
			return "of$"
		if ("the$".startsWith(str))
			return "the$"
		if ("in$".startsWith(str))
			return "in$"
	}

	function isUndecomposableNode(node)
	{
		return !reverseDecompose(node.id)
	}

	function LCP(a, b)
	{
		for (var i = 0, min = Math.min(a.length, b.length); i < min && a[i] === b[i]; i++);
		return i;
	}
	const firstEdge = new Map()

	for (const edge of trie.edges)
		if (!firstEdge.has(edge.source))
			firstEdge.set(edge.source, edge)

	let prev = "[ROOT]"

	const map = new Map(Object.entries({
		wo: "world", we: "west", w$: "w",
		wil: "william", wis: "wisconsin", wit: "with",
		wikt: "wiktor", wiks: "wikstroemia", wike: "wike",
		wikim: "wikimedia", wiki$: "wiki", wikil: "wikileaks",
		wikipro: "wikiprofessional", wikipilipinas: "wikipilipinas",
		wikipediocracy: "wikipediocracy",
		"wikipedia ": "wikipedia wikipedia", wikipediafs: "wikipediafs", wikipedias: "wikipedias",


		le: "league", la: "la", lo: "love",
		lin: "line", lit: "little", lif: "life",
		lisa: "lisa", lisb: "lisbon", lise: "lise",
		"list ": "list of", listi: "listings", liste: "listed",
		"list a": "list a", "list f": "list for", "list d": "list data",
		"list ob": "list observatory",

		op: "open", ol: "olympics", on: "on",
		"of ": "of the", off: "office", ofc: "ofc",


		i$: "i",
		"te": "team",
		"to": "township",
		"tv": "tv",
		"tho": "thomas",
		"thr": "three",
		"tha": "that",
		"the ": "the united",
		"thea": "theatre",
		"theo": "theory",
		"is": "island",
		"ii": "ii",
		"in ": "in the",
		"int": "international",
		"ins": "institute",

		w: "wikipedia",
		l: "list",
		o: "of",
		t: "the",
		i: "in",
		f: "film",
	}))

	const map2 = new Map(Object.entries({
		"list observatory": 4,
		wikipediafs: 3,
		wikipedias: 4,
		wikipilipinas: 3,

		"listings": 4,
		"listed": 3,
	}))

	let oldEdgesLen = trie.edges.length
	let oldNodesLen = trie.nodes.length

	for (let i = trie.nodes.length; 0 <-- i; )
	{
		const node = trie.nodes[i]

		if (isUndecomposableNode(node) || node.id.length === 1 || node.id === "list ")
		{
			const decomposedName = map.get(node.id)
			if (!decomposedName) throw `${node.id} has nothing to decompose into`;

			trie.nodes.push({ id: `d_${decomposedName}$`, label: `“${decomposedName}$”:${node.size}`, x: node.x, y: node.y, size: 1, forceLabel: 0 })
		}
	}

	{
		let node = trie.nodes[0]
		trie.nodes.push({ id: `d_[ROOT]$`, label: `“”`, x: node.x, y: node.y, size: 1, forceLabel: 0 })
		trie.edges.push({
			source: `d_[ROOT]$`,
			target: `d_wikipedia$`,
			id: `d_${decomposed_id++}`,
			type: "arrow",
			label: `(0, “wikipedia”)`,
			active_color: ORIGINAL_COLOR,
			targetLabel: 1
		})
	}

	for (let i = trie.edges.length - 1, q = 0; 0 <= --i; )
	{
		const edge = trie.edges[i]

		if (edge.type === "dashedArrow")
		{
			if (edge.source.length === 1)
			{
				const source = map.get(edge.source[0])
				const target = map.get(edge.target)
				trie.edges.push({
					source: `d_${source}$`,
					target: `d_${target}$`,
					id: `d_${decomposed_id++}`,
					type: "arcArrow",
					label: `(0, “${target}”)`,
					active_color: ORIGINAL_COLOR,
					targetLabel: 4
				})
			}
			else
			{
				let originalSource = reverseDecompose(edge.source)
				let source = `d_${originalSource}`
				const target = map.get(edge.target)

				if (originalSource && trie.nodes.find(x => x.id === source).y !== trie.nodes.find(x => x.id === edge.target).y)
				{
					const lcp = LCP(target, originalSource)

					trie.edges.push({ source, target: `d_${target}$`, id: `d_${decomposed_id++}`, type: `arcArrow`, label: `(${lcp}, “${target
						// .slice(lcp)
					}”)`, active_color: ORIGINAL_COLOR, targetLabel: target === "list of" ? 4 : 3 })
				}
				else
				{
					originalSource = map.get(edge.source)
					source = `d_${originalSource}$`
					const lcp = LCP(target, originalSource)

					trie.edges.push(
						{
							source, target: `d_${target}$`,
							id: `d_${decomposed_id++}`, type: `arcArrow`,
							label: `(${lcp}, “${target}”)`, //.slice(LCP)
							active_color: ORIGINAL_COLOR,
							targetLabel: 7 ^ (map2.get(target) || ((++q % 2) + 3)),
							flipMe: true
						}
					)
				}
			}
		}
		// else if (firstEdge.get(edge.source) === edge)
		// {
		// }
	}

	{
		const scores = new Map()

		for (let i = oldNodesLen, len = trie.nodes.length; i < len; i++)
		{
			const node = trie.nodes[i]
			scores.set(node.id, node.score = parseInt(node.label.split(":")[1]))
		}

		for (let i = oldEdgesLen, len = trie.edges.length; i < len; i++)
		{
			const edge = trie.edges[i]
			edge.score = scores.get(edge.target)
		}
	}

	const maxEdges = new Map()

	for (let i = oldEdgesLen, len = trie.edges.length; i < len; i++)
	{
		const edge = trie.edges[i]
		const arr = maxEdges.get(edge.source)

		if (arr === undefined)
			maxEdges.set(edge.source, [ edge ])
		else
		{
			let i = arr.push(edge) - 1
			while (--i >= 0 && arr[i].score < edge.score)
				arr[i + 1] = arr[i]

			arr[i + 1] = edge

			// arr.sort((a, b) => b.score - a.score)
		}
	}

	const maxEdgeSet = new Set()

	for (const [source, arr] of maxEdges)
	{
		// console.log(source, arr)
		maxEdgeSet.add(arr[0].target)

		for (let i = arr.length; 0 <-- i; )
		{
			const mySource = arr[i - 1].target
			const target = arr[i].target

			const trimmedSource = source.slice(2, -1)
			const trimmedTarget = target.slice(2, -1)

			trie.edges.push({
				source: mySource,
				target,
				id: `r_${decomposed_id++}`,
				type: "dashedArrow",
				label: `(${LCP(trimmedSource, trimmedTarget)}, “${trimmedTarget}”)`,
				active_color: ORIGINAL_COLOR,
				targetLabel: 1
			})

			// console.log(ob)
		}
	}

	function isRecomposedEdge(edge)
	{
		return edge.id.startsWith("r_") || maxEdgeSet.has(edge.target)
	}
}

for (const node of trie.nodes)
{
	node.x = Math.floor(node.x / 90112 + 0.5) * 90112
		+ ((node.id === "wikipediocracy") * 90112)
}

// trie.nodes.push({ id: `d_wikipedia$`, label: `"wikipedia$":1220297`, x: 0, y: 32768, size: 1220297, forceLabel: 0 })
// trie.edges.push({ source: `[ROOT]`, target: `d_wikipedia$`, id: `d_${decomposed_id++}`, type: `arrow`, label: "(0, \"wikipedia\")", active_color: ORIGINAL_COLOR })

// trie.nodes.push({ id: `d_list$`, label: `"list$":101139`, x: 0, y: 32768, size: 1220297, forceLabel: 0 })

const NODE_SIZE = 6

for (const node of trie.nodes)
{
	// if (node.size == 1220297) node.size /= 10; // shrink the node that's 10x larger than the rest
	node.size = NODE_SIZE;
	node.y *= 3;
}

for (const edge of trie.edges)
	edge.size = 2

const parentLookup = new Map()
const nodeDepths = new Map();

for (const edge of trie.edges)
{
	parentLookup.set(edge.target, edge.source)
}

const DOWNWARD_SHIFT = 0

for (const node of trie.nodes) {
	node.LCRS_x = node.x + 90112*0.5
	node.LCRS_y = node.y - DOWNWARD_SHIFT
}

for (const node of trie.nodes)
{
	if (node.id.startsWith("d_")) {}
	else
	{
		if (node.id === "[ROOT]")
		{
			node.x = 720896
			nodeDepths.set(node.id, 0)
		}
		else
		{
			const parentStr = parentLookup.get(node.id)
			const depth = 1 + nodeDepths.get(parentStr)
			nodeDepths.set(node.id, depth)
			if (depth === 1)
			{
				node.x += 90112
			} else if (depth > 2)
			{
				node.x -= (depth - 2) * 90112
			}
		}

		node.x -= 90112*1
	}
}

const shuffle = new Map([
	['w', 90112 * 7],
	['l', 90112 * -0.25],
	['o', 90112 * 6],
	['t', 90112 * (-5 + 3.5)],
	['i', 90112 * -15.5],
	['f', 90112 * -3],
])

const shuffle2 = new Map([
	['l', 90112 * 1],
	['i', 90112 * 1.5],
	['in', 90112 * 1],
	['i$', 90112 * 2],
	['is', 90112 * -2],
	['ii', 90112 * -1],

	['in$', 90112 * 2],
	['in ', 90112 * 1.5],
	['int', 90112 * -1],
	['ins', 90112 * -1.5],

	['li', 90112 * 1],
	['le', 90112 * 2],
	['la', 90112 * -2],
	['lo', 90112 * -1],

	['lis', 90112 * 1],
	['lin', 90112 * 2],
	['lit', 90112 * -2],
	['lif', 90112 * -1],

	['list', 90112 * 3],
	['lisa', 90112 * 1],
	['lisb', 90112 * -2],
	['lise', 90112 * -2],

	['list$', 90112 * (3 + 2)],
	['list ', 90112 * (1 + 2)],
	['listi', 90112 * (-2 + 2)],
	['liste', 90112 * (-2 + 2)],

	['list o', 90112 * (1 + 2)],
	['list a', 90112 * (1 + 2)],
	['list f', 90112 * (-2 + 2)],
	['list d', 90112 * (0 + 2)],

	['list of', 90112 * (2 + 2)],
	['list ob', 90112 * (0 + 2)],
	['list of$', 90112 * (3 + 2)],

	['th', 90112 * 1],
	['te', 90112 * 2],
	['to', 90112 * 0],
	['tv', 90112 * -3],

	['the', 90112 * 1],
	['tho', 90112 * 2],
	['thr', 90112 * -2],
	['tha', 90112 * -1],

	['the$', 90112 * 1],
	['the ', 90112 * 2],
	['thea', 90112 * 0],
	['theo', 90112 * -3],

	['wi', 90112 * 1],
	['wo', 90112 * 2],
	['we', 90112 * 0],
	['w$', 90112 * -3],

	['wik', 90112 * 1],
	['wil', 90112 * 2],
	['wis', 90112 * -2],
	['wit', 90112 * -1],

	['wiki', 90112 * 3],
	['wikt', 90112 * 1],
	['wiks', 90112 * -2],
	['wike', 90112 * -2],

	['wikip', 90112 * (1 + 3)],
	['wikim', 90112 * (2 + 3)],
	['wiki$', 90112 * (-2 + 3)],
	['wikil', 90112 * (-1 + 3)],


	['wikipedi', 90112 * (1 + 4)],
	['wikipro', 90112 * (1 + 4)],
	['wikipilipinas', 90112 * (-2 + 3)],

	['wikipedia', 90112 * (1 + 5)],
	['wikipediocracy', 90112 * (-2 + 5)],

	['wikipedia$', 90112 * (1 + 5)],
	['wikipedia ', 90112 * (2 + 5)],
	['wikipediafs', 90112 * (0 + 5)],
	['wikipedias', 90112 * (-3 + 5)],

	['of', 90112 * 1],
	['op', 90112 * 2],
	['ol', 90112 * -2],
	['on', 90112 * -1],

	['of$', 90112 * 3],
	['of ', 90112 * 1],
	['off', 90112 * -2],
	['ofc', 90112 * -2],

])

{
	for (const node of trie.nodes)
	{
		node.x = Math.floor(node.x / 90112 + 0.5) * 90112
	}
}
for (const node of trie.nodes)
{
	if (node.id.startsWith("d_")) {}
	else if (node.id === "[ROOT]") {}
	else
	{
		node.x += shuffle.get(node.id[0])

		node.x += shuffle2.get(node.id) || 0
	}
}

for (const node of trie.nodes) {
	node.original_x = node.x
	node.original_y = node.y
}

var defaultEdgeLabelSize = 28

// // Instantiate sigma:
const s = new sigma({
	graph: trie,
	renderer: {
		container: document.getElementById('graph-container'),
		type: 'canvas'
	},
	settings: {
		animationsTime: 1,

		minEdgeSize: 2.5,
		maxEdgeSize: 2.5,
		// minNodeSize: 7,
		// maxNodeSize: 7,

		defaultLabelSize: 28,
		defaultEdgeLabelSize: defaultEdgeLabelSize,
	}
});

// document.addEventListener("keydown", event => {
//   if (event.isComposing || event.keyCode === 229) {
//     return;
//   }

//   if (event.key === "`") {
// 	  console.log('exporting...');
// 	  const output = s.toSVG({ download: true, filename: 'mygraph.svg' });
// 	  console.log(output);
//   }
// });



const firstEdge = new Map()

for (const edge of s.graph.edges())
{
	edge.edgeActiveColor = "edge"
	// edge.size = 12000000000000
	// edge.edgeLabelSizePowRatio = 255;
	// edge.labelSizePowRatio = 255;
	if (!firstEdge.has(edge.source))
	{
		firstEdge.set(edge.source, edge)
	}
}

// for (const node of s.graph.nodes()) {
// 	if ("wikipedia".startsWith(node.id)) {

// 	}
// }
// s.graph.addNode({ id: `d_wikipedia$`, label: `"wikipedia$":1220297`, x: 0, y: 3*32768, size: 1, forceLabel: 0 })
// s.graph.addEdge({ source: `[ROOT]`, target: `d_wikipedia$`, id: `d_${decomposed_id++}`, type: `arrow`, label: "(0, \"wikipedia\")", active_color: ORIGINAL_COLOR })

// function findSubtree(target)
// {
// 	const nodes = []
// 	const edges = []
// 	for (
// 		let t = s.graph.nodes(target).label.split(":")[1],
// 		edge = { target }, node;
// 		(nodes[nodes.length] = node = s.graph.nodes(edge.target)) &&
// 		node.label.split(":")[1] === t && !node.label.split(":")[0].endsWith('$"') &&
// 		(edges[edges.length] = edge = firstEdge.get(node.id));
// 	);
// 	return { nodes, edges }
// }

// function subtreeAdjacencies(subtree, doNotIncludeTopAdjacency)
// {
// 	// Quadratic complexity, buyer beware, could be improved but doesn't run in real time anyway
// 	// console.log(subtree)
// 	const nodes = []
// 	const edges = []

// 	for (const edge of s.graph.edges())
// 	{
// 		const i = subtree.nodes.indexOf(s.graph.nodes(edge.source))

// 		if (
// 			i !== -1
// 			&& (i !== 0 || !doNotIncludeTopAdjacency)
// 			&& (i !== subtree.nodes.length - 1 || -1 === edge.target.indexOf(edge.source)) // don't grab the edge underneath the last node
// 			&& (firstEdge.get(edge.source) === edge || edge.type === "dashedArrow") // don't grab the non-peer edges
// 		)
// 		{
// 			edges.push(edge)
// 			const node = s.graph.nodes(edge.target)
// 			if (subtree.nodes.indexOf(node) === -1)
// 				nodes.push(node)
// 		}
// 	}

// 	return { nodes, edges }
// }

// function deselectSubtree(subtree)
// {
// 	// let x = subtree.nodes[0].forceLabel ^ 2
// 	for (const edge of subtree.edges)
// 	{
// 		edge.active_color = DISABLED_COLOR
// 	}
// 	for (let i = 1; i < subtree.nodes.length; i++)
// 	{
// 		const node = subtree.nodes[i]
// 		node.color = DISABLED_COLOR
// 		node.forceLabel = 0
// 	}
// 	// subtree.nodes[0].forceLabel = x || 4
// }

// function deselectAdjacencies(adjacencies)
// {
// 	for (const edge of adjacencies.edges)
// 	{
// 		edge.active_color = DISABLED_COLOR
// 	}
// 	for (const node of adjacencies.nodes)
// 	{
// 		node.color = DISABLED_COLOR
// 		node.forceLabel = 0
// 	}
// }

// function selectSubtree(subtree)
// {
// 	// let x = subtree.nodes[0].forceLabel ^ 2

// 	for (const edge of subtree.edges)
// 	{
// 		edge.active_color = SELECTED_COLOR
// 	}
// 	for (const node of subtree.nodes)
// 	{
// 		if (node.color === DISABLED_COLOR) node.color = SELECTED_COLOR
// 		node.forceLabel = 1
// 	}

// 	// subtree.nodes[0].forceLabel = x || 4
// 	subtree.nodes[subtree.nodes.length - 1].color = PICKED_COLOR
// 	// subtree.nodes[subtree.nodes.length - 1].forceLabel = 2
// }

// function selectAdjacencies(adjacencies)
// {
// 	for (const edge of adjacencies.edges)
// 	{
// 		edge.active_color = SELECTED_COLOR
// 	}
// 	for (const node of adjacencies.nodes)
// 	{
// 		node.color = SELECTED_COLOR
// 		node.forceLabel = 3
// 	}
// }

// const root_subtree = findSubtree("[ROOT]")
// const root_adjacencies = subtreeAdjacencies(root_subtree)
// const l_subtree = findSubtree("l")
// const l_adjacencies = subtreeAdjacencies(l_subtree)
// const list_of_subtree = findSubtree("list ")
// const list_of_adjacencies = subtreeAdjacencies(list_of_subtree)
// const o_subtree = findSubtree("o")
// const o_adjacencies = subtreeAdjacencies(o_subtree)
// const t_subtree = findSubtree("t")
// const t_adjacencies = subtreeAdjacencies(t_subtree)



function isDecomposedNode(node) { return node.id.startsWith("d_") && node.id !== "d_[ROOT]$" }
function isNonDecomposedNode(node) { return !node.id.startsWith("d_") }
function isUnsortedEdge(edge) { return edge.type === "arrow" && !edge.id.startsWith("d_") }
function isSortedEdge(edge) { return (firstEdge.get(edge.source) === edge || edge.type === "dashedArrow") && !edge.id.startsWith("d_") }
function isDecomposedEdge(edge) { return edge.id.startsWith("d_") }

const nonDecomposedNodes = s.graph.nodes().filter(isNonDecomposedNode)
const decomposedNodes = s.graph.nodes().filter(isDecomposedNode)
const unsortedEdges = s.graph.edges().filter(isUnsortedEdge)
const sortedEdges = s.graph.edges().filter(isSortedEdge)
const decomposedEdges = s.graph.edges().filter(isDecomposedEdge)
const recomposedNodes = decomposedNodes
const recomposedEdges = s.graph.edges().filter(isRecomposedEdge)

const filter = new sigma.plugins.filter(s)

filter
	.edgesBy(isUnsortedEdge, "unsortedEdges")
	.nodesBy(isNonDecomposedNode, "nonDecomposedNodes")
	.apply()

// console.log(decomposedEdges)

// const state_changers = [function() {}];

// state_changers[18] = function(oldState)
// {
// 	for (const node of s.graph.nodes())
// 	{
// 		if (node.id.startsWith("d_w"))
// 		{
// 			console.log(node)
// 			// node.x *= 2
// 		}
// 	}
// }

// state_changers[17] = function(oldState)
// {
// 	deselectSubtree(root_subtree)
// 	deselectAdjacencies(root_adjacencies)
// 	deselectSubtree(l_subtree)
// 	deselectAdjacencies(l_adjacencies)
// 	deselectSubtree(list_of_subtree)
// 	deselectAdjacencies(list_of_adjacencies)
// 	deselectSubtree(o_subtree)
// 	deselectAdjacencies(o_adjacencies)
// 	deselectSubtree(t_subtree)

// 	for (const node of s.graph.nodes())
// 	{
// 		node.color = ORIGINAL_COLOR
// 	}

// 	for (const edge of s.graph.edges())
// 	{
// 		edge.active = false
// 	}

// 	for (const node of root_subtree.nodes)
// 	{
// 		node.forceLabel = 0
// 	}

// 	// console.log(firstEdge)

// 	filter
// 	.undo("peer")
// 	.edgesBy(function(edge) { return edge.id.startsWith("d_") }, "d_edges")
// 	.nodesBy(function(node) { return node.id.startsWith("d_") }, "d_nodes")
// 	.apply()
// }

// state_changers[1] = function(oldState)
// {
// 	if (oldState === 2)
// 	{
// 		filter
// 			.undo("peer")
// 			.edgesBy(function(edge)
// 			{
// 				return edge.type === "arrow" && !edge.id.startsWith("d_")
// 			}, 'tree')
// 			.apply()

// 		setTimeout(function()
// 		{
// 			sigma.plugins.animate(
// 				s,
// 				{
// 					x: "original_x",
// 					// size: prefix + 'size',
// 					// color: prefix + 'color'
// 				},
// 				{
// 					nodes: nonDecomposedNodes,
// 					easing: 'cubicOut',
// 					// duration: 2000,
// 					// onComplete: function() {
// 						// do stuff here after animation is complete
// 					// }
// 				}
// 			);
// 		}, waitTime)
// 	}
// }

// state_changers[2] = function(oldState)
// {
// 	if (oldState === 1)
// 	{
// 		// filter
// 		// 	.undo("tree")
// 		// 	.edgesBy(function(edge)
// 		// 	{
// 		// 		return (firstEdge.get(edge.source) === edge || edge.type === "dashedArrow") && !edge.id.startsWith("d_")
// 		// 	}, "peer")
// 		// 	.apply()

// 		setTimeout(function()
// 		{
// 			sigma.plugins.animate(
// 				s,
// 				{
// 					x: "LCRS_x",
// 					// size: prefix + 'size',
// 					// color: prefix + 'color'
// 				},
// 				{
// 					nodes: nonDecomposedNodes,
// 					// easing: 'cubicInOut',
// 					// duration: 2000,
// 					// onComplete: function() {
// 						// do stuff here after animation is complete
// 					// }
// 				}
// 			);
// 		}, waitTime)
// 	}
// }

// state_changers[3] = function(oldState)
// {
// 	if (oldState === 4)
// 	{
// 		for (const node of s.graph.nodes())
// 		{
// 			node.color = ORIGINAL_COLOR
// 		}

// 		for (const edge of s.graph.edges())
// 		{
// 			edge.active = false
// 		}
// 	}
// }

// state_changers[4] = function(oldState)
// {
// 	for (const node of s.graph.nodes())
// 	{
// 		node.color = DISABLED_COLOR
// 	}

// 	for (const edge of s.graph.edges())
// 	{
// 		edge.active = true
// 		edge.active_color = DISABLED_COLOR
// 	}

// 	for (const edge of root_subtree.edges)
// 	{
// 		edge.active_color = SELECTED_COLOR
// 	}

// 	for (const node of root_subtree.nodes)
// 	{
// 		node.color = SELECTED_COLOR
// 	}

// 	s.graph.nodes("wikipedia").color = PICKED_COLOR
// }

// state_changers[5] = function(oldState)
// {
// 	for (const edge of root_adjacencies.edges)
// 	{
// 		edge.active_color = SELECTED_COLOR
// 	}
// 	for (const node of root_adjacencies.nodes)
// 	{
// 		node.color = SELECTED_COLOR
// 		node.forceLabel = 0
// 	}
// 	for (const node of root_subtree.nodes)
// 	{
// 		node.forceLabel = 0
// 	}
// 	s.graph.nodes("wikipedia").color = PICKED_COLOR
// }

// // I'm not trying to win any awards for this code, just get it working
// state_changers[6] = function(oldState)
// {
// 	if (oldState === 7)
// 	{
// 		deselectSubtree(l_subtree)
// 		deselectAdjacencies(l_adjacencies)
// 	}
// 	selectSubtree(root_subtree)
// 	selectAdjacencies(root_adjacencies)
// }

// state_changers[7] = function(oldState)
// {
// 	if (oldState === 8)
// 	{
// 		deselectSubtree(list_of_subtree)
// 		deselectAdjacencies(list_of_adjacencies)
// 	}
// 	selectAdjacencies(root_adjacencies)
// 	selectSubtree(l_subtree)
// 	selectAdjacencies(l_adjacencies)
// }

// state_changers[8] = function(oldState)
// {
// 	if (oldState === 9)
// 	{
// 		deselectSubtree(o_subtree)
// 		deselectAdjacencies(o_adjacencies)
// 	}
// 	selectAdjacencies(root_adjacencies)
// 	selectSubtree(l_subtree)
// 	selectAdjacencies(l_adjacencies)
// 	selectSubtree(list_of_subtree)
// 	selectAdjacencies(list_of_adjacencies)
// }

// state_changers[9] = function(oldState)
// {
// 	if (oldState === 10)
// 	{
// 		deselectSubtree(t_subtree)
// 		// deselectAdjacencies(t_adjacencies)
// 	}
// 	selectAdjacencies(l_adjacencies)
// 	selectSubtree(o_subtree)
// 	selectAdjacencies(o_adjacencies)
// }

// state_changers[10] = function(oldState)
// {
// 	selectSubtree(t_subtree)
// 	// selectAdjacencies(t_adjacencies)
// }

const controlPanes = [...document.getElementsByClassName("control-pane")]

function createButton(className, onClick)
{
	const button = document.createElement("button")
	button.className = className
	button.type = "button"
	button.addEventListener('click', onClick)
	return button
}

function createMinimize(onClick)
{
	const button = document.createElement("button")
	button.className = "minimize"
	button.type = "button"
	button.addEventListener('click', onClick)

	button.innerHTML = `<svg height="24" width="24" viewBox="0 0 96 96" xmlns="http://www.w3.org/2000/svg"><g><path d="M30,60H6A6,6,0,0,0,6,72H24V90a6,6,0,0,0,12,0V66A5.9966,5.9966,0,0,0,30,60Z"/><path d="M90,60H66a5.9966,5.9966,0,0,0-6,6V90a6,6,0,0,0,12,0V72H90a6,6,0,0,0,0-12Z"/><path d="M66,36H90a6,6,0,0,0,0-12H72V6A6,6,0,0,0,60,6V30A5.9966,5.9966,0,0,0,66,36Z"/><path d="M30,0a5.9966,5.9966,0,0,0-6,6V24H6A6,6,0,0,0,6,36H30a5.9966,5.9966,0,0,0,6-6V6A5.9966,5.9966,0,0,0,30,0Z"/></g></svg>`

	// const svg = document.createElement("svg")
	// svg.height = "24"
	// svg.width = "24"
	// svg.viewBox = "0 0 96 96"
	// svg.xmlns = "http://www.w3.org/2000/svg";

	// svg.innerHTML = `<g><path d="M30,60H6A6,6,0,0,0,6,72H24V90a6,6,0,0,0,12,0V66A5.9966,5.9966,0,0,0,30,60Z"/><path d="M90,60H66a5.9966,5.9966,0,0,0-6,6V90a6,6,0,0,0,12,0V72H90a6,6,0,0,0,0-12Z"/><path d="M66,36H90a6,6,0,0,0,0-12H72V6A6,6,0,0,0,60,6V30A5.9966,5.9966,0,0,0,66,36Z"/><path d="M30,0a5.9966,5.9966,0,0,0-6,6V24H6A6,6,0,0,0,6,36H30a5.9966,5.9966,0,0,0,6-6V6A5.9966,5.9966,0,0,0,30,0Z"/></g>`

	return button
}

function resetGraph(context)
{
	for (const node of context.nodes)
	{
		node.color = ORIGINAL_COLOR
		node.forceLabel = 0
	}

	for (const edge of context.edges)
	{
		edge.active = false
	}
}

const forceLabelOverrides = new Map([
	["ii", 8],
	["[ROOT]", 9],
	["i", 6],
	["l", 6],
	["t", 7],
	["i$", 11],
	["w$", 7],
	["of", 7],
	["te", 8],
	["le", 6],
	["lo", 8],
	["is", 8],
	["tho", 8],
	["theo", 10],
	["tha", 8],
	["wit", 8],
	["wis", 7],
	["wik", 7],
	["wikt", 8],
	["wike", 8],
	["wiks", 9],
	["wil", 8],
	["list", 6],
	["wo", 8],
	["we", 8],
	["w", 7],
	["wiki", 14],
	["wikip", 7],
	["wikipedi", 7],
	["wikipedia", 7],

	["lisa", 11],
	["lise", 8],
	["lisb", 8],
	["listi", 8],
	["list f", 8],
	["list ob", 8],

	["lin", 11],
	["in ", 12],
	["int", 13],
	["ins", 11],
])


{
	const scores = new Map()

	for (const node of decomposedNodes)
	{
		scores.set(node.id, node.score = parseInt(node.label.split(":")[1]))
	}

	for (const edge of decomposedEdges)
		edge.score = scores.get(edge.target)
}
for (let [i, j, str] of [[0, 0, "d_wikipedia$"], [0,0,"d_list$"], [0, 0, "d_of$"], [0, 0, "d_in$"]])
{
	const targetNodes = new Set(
		decomposedEdges
			.filter(edge => edge.source === str)
			.map(edge => edge.target)
	)

	const targetLayer = decomposedNodes.filter(node => targetNodes.has(node.id))
	prev = 0

	targetLayer.sort((a, b) => b.score - a.score)
	const map = new Map()

	for (let k = 0; k < targetLayer.length; k++)
	{
		const node = targetLayer[k]
		const y = node.decomposed_y = 98304 * ++i
		if (node.id === "d_list of$")
			i += 2
		if (k !== j)
			map.set(node.id, y)
	}

	// console.log(targetLayer)
	// console.log(map)

	const map2 = new Map()

	for (const edge of decomposedEdges)
	{
		if (map.has(edge.source))
		{
			map2.set(edge.target, map.get(edge.source))
		}
	}

	for (const edge of decomposedEdges)
	{
		if (map2.has(edge.source))
		{
			map2.set(edge.target, map2.get(edge.source))
		}
	}

	// console.log(map2)

	for (const node of decomposedNodes)
	{
		if (map2.has(node.id))
		{
			node.decomposed_y = map2.get(node.id)
			// console.log(node.id, node.y, node.decomposed_y)
		}
	}
}

let list_of_nodeIds; {
	const edges = decomposedEdges
		.filter(edge => edge.source === "d_list of$")

	list_of_nodeIds = new Set()
	for (const edge of edges)
	{
		list_of_nodeIds.add(edge.target)
		// edge.type = "curvedArrow"
	}
	// edges.find(edge => edge.target === "d_list a$").type = "arrow"
}

for (let i = 0; i < 2; i++)
	for (const edge of decomposedEdges)
		if (list_of_nodeIds.has(edge.source))
			list_of_nodeIds.add(edge.target)

// list_of_nodeIds.add("d_list of$")

for (const node of decomposedNodes)
{
	if (list_of_nodeIds.has(node.id))
	{
		node.decomposed_y = node.y - 98304 * 4
	}
}

{
	const node = decomposedNodes.find(node => node.id === "d_list of$")
	node.decomposed_y = node.y - 98304 * 4
}

{
	for (const node of decomposedNodes)
	{
		if (node.id !== "d_of$")
		switch (node.id[2])
		{
			case "o":
			case "t":
			case "i":
			case "f":
				node.decomposed_y = node.y + 98304 * 3
				continue
		}


	}

	let p = 8
	const lookup_x = new Map([
		["d_list$", 90112],
		["d_of$", 90112*5],
		["d_the$", 90112*8],

		["d_listings$", 90112*p],
		["d_list a$", 90112*p],
		["d_list observatory$", 90112*p++],

		["d_list for$", 90112*p++],
		["d_listed$", 90112*p],

		["d_list data$", 90112*p],

		["d_the$", 90112*8],
		["d_of the$", 90112*8],
		["d_open$", 90112*8],



		["d_olympics$", 90112*9],
		["d_office$", 90112*9],

		["d_on$", 90112*10],
		["d_ofc$", 90112*10],

		["d_in$", 90112*11],
		["d_team$", 90112*11],
		["d_thomas$", 90112*11],
		["d_the united$", 90112*11],

		["d_township$", 90112*12],
		["d_three$", 90112*12],
		["d_theatre$", 90112*12],

		["d_tv$", 90112*13],
		["d_that$", 90112*13],
		["d_theory$", 90112*13],


		["d_film$", 90112*14],
		["d_i$", 90112*14],
		["d_in the$", 90112*14],

		["d_island$", 90112*15],
		["d_international$", 90112*15],

		["d_ii$", 90112*16],
		["d_institute$", 90112*16],
	])

	const lookup_y = new Map([
		["d_open$", 98304*6],
		["d_olympics$", 98304*6],
		["d_on$", 98304*6],

		["d_of the$", 98304*5],
		["d_office$", 98304*5],
		["d_ofc$", 98304*5],


		["d_in the$", 98304*5],
		["d_international$", 98304*5],
		["d_institute$", 98304*5],

		["d_i$", 98304*6],
		["d_island$", 98304*6],
		["d_ii$", 98304*6],
	])

	for (const node of decomposedNodes)
	{
		let x = lookup_x.get(node.id)
		if (x !== undefined)
			node.decomposed_x = x

		let y = lookup_y.get(node.id)
		if (y !== undefined)
			node.decomposed_y = y
	}
}

for (const node of decomposedNodes)
{
	if (node.decomposed_x === undefined)
	{
		node.decomposed_x = node.x
	}

	if (node.decomposed_y === undefined)
	{
		node.decomposed_y = node.y
	}

	node.decomposed_y -= DOWNWARD_SHIFT

	// node.original_y = node.y
	// LCRS_y
}

const RECOMPOSED_ROOT_LABEL = 9
const recomposedRoot = s.graph.nodes().find(node => node.id === "d_wikipedia$")
recomposedRoot.decomposed_x -= 90112
recomposedRoot.forceLabel = RECOMPOSED_ROOT_LABEL
recomposedRoot.isRoot = true

function getForceLabelPosition(id)
{
	return forceLabelOverrides.get(id) ||
		(id.match(/^(of|in|the|wiki)./) ? 8 : 7)
}

const unsortedContext = {
	nodes: nonDecomposedNodes,
	edges: unsortedEdges,
	getForceLabelPosition
}

const sortedContext = {
	nodes: nonDecomposedNodes,
	edges: sortedEdges,
	getForceLabelPosition: function(id, edgeTypeThatLeadsToThisNode)
	{
		switch (edgeTypeThatLeadsToThisNode)
		{
			case "dashedArrow":
				return 9
			case "arrow":
				return 6
		}
	}
}

const decomposedContext = {
	nodes: decomposedNodes,
	edges: decomposedEdges,
	getForceLabelPosition
}

const path = ["[ROOT]", "w", "wi", "wik", "wiki", "wikip", "wikipedi", "wikipedia", "wikipedia$", "l", "li", "lis", "list", "list$", "list ", "list o", "list of", "list of$", "o", "of", "of$", "t", "th", "the", "the$"]

function highlightTreeForSources(sources, context, lastSourceDisabledBranchPoints = "")
{
	const selectedNodes = new Map()
	for (const edge of context.edges)
	{
		if (sources.has(edge.source) && (!lastSourceDisabledBranchPoints.startsWith(edge.source) || edge.type !== "dashedArrow"))
		{
			edge.active_color = sources.has(edge.target)
				? PICKED_COLOR
				: SELECTED_COLOR
			selectedNodes.set(edge.target, edge.type)
		}
		else
			edge.active_color = DISABLED_COLOR

		edge.active = true
	}

	for (const node of context.nodes)
	{
		if (selectedNodes.has(node.id) || sources.has(node.id))
		{
			node.color = sources.has(node.id) ? PICKED_COLOR : SELECTED_COLOR
			node.forceLabel = context.getForceLabelPosition(node.id, selectedNodes.get(node.id))
		}
		else
		{
			node.forceLabel = 0
			node.color = DISABLED_COLOR
		}
	}
}


const state_transitions = []

state_transitions.push(function() {})
state_transitions.push(function() {})

state_transitions.push(function(wentBackwards)
{
	if (wentBackwards)
	{
		resetGraph(unsortedContext)
		s.refresh()
	}
})

state_transitions.push(function(wentBackwards) // EXAMPLE TRAVERSAL
{
	for (const node of nonDecomposedNodes)
	{
		if (node.id === "[ROOT]" || node.id === "l" || node.id === "li")
			node.color = PICKED_COLOR
		else if (node.id.startsWith("li"))
			node.color = SELECTED_COLOR
		else
			node.color = DISABLED_COLOR
	}

	for (const edge of unsortedEdges)
	{
		edge.active = true

		if (edge.target === "l" || edge.target === "li")
			edge.active_color = PICKED_COLOR
		else if (edge.target.startsWith("li"))
			edge.active_color = SELECTED_COLOR
		else
			edge.active_color = DISABLED_COLOR
	}

	if (wentBackwards)
	{
		for (const node of nonDecomposedNodes)
			node.forceLabel = 0
	}

	s.refresh()
})

state_transitions.push(function(wentBackwards) // The Completion Trie
{
	resetGraph(unsortedContext)

	// Make all nodes display a score
	for (const node of nonDecomposedNodes)
	{
		node.forceLabel = getForceLabelPosition(node.id)
	}

	s.refresh()
})

for (let i = 0; ++i <= path.length; )
{
	if ((10 <= i && i <= 13) || (15 <= i && i <= 17) || (19 <= i && i <= 20) || (22 <= i && i <= 24)) continue;
	state_transitions.push(function()
	{
		highlightTreeForSources(new Set(path.slice(0, i)), unsortedContext)
		s.refresh()
	})
}

state_transitions.push(function(wentBackwards) {
	if (wentBackwards)
	{
		setTimeout(function()
		{
			sigma.plugins.animate(
				s,
				{
					x: "original_x",
					y: "original_y",
					// size: prefix + 'size',
					// color: prefix + 'color'
				},
				{
					nodes: nonDecomposedNodes,
					// easing: 'cubicInOut',
					// duration: 2000,
					// onComplete: function() {
						// do stuff here after animation is complete
					// }
				}
			);
		}, WAIT_TIME)
	}
	else
	{
		resetGraph(unsortedContext)
		s.refresh()
	}
})

state_transitions.push(function(wentBackwards)
{
	if (wentBackwards)
	{
		filter
			.undo("sortedEdges")
			.edgesBy(isUnsortedEdge, "unsortedEdges")
			.apply()
	}
	else
	{
		setTimeout(function()
		{
			sigma.plugins.animate(
				s,
				{
					x: "LCRS_x",
					y: "LCRS_y",
					// size: prefix + 'size',
					// color: prefix + 'color'
				},
				{
					nodes: nonDecomposedNodes,
					// easing: 'cubicInOut',
					// duration: 2000,
					// onComplete: function() {
						// do stuff here after animation is complete
					// }
				}
			);
		}, WAIT_TIME)
	}
	s.refresh()
})

state_transitions.push(function(wentBackwards)
{
	if (!wentBackwards)
	{
		filter
			.undo("unsortedEdges")
			.edgesBy(isSortedEdge, "sortedEdges")
			.apply()

	}
	else resetGraph(sortedContext)
	s.refresh()
})

state_transitions.push(function(wentBackwards)
{
	highlightTreeForSources(new Set(path.slice(0, 9)), sortedContext)
	s.refresh()
})

for (const endState of [14, 18, 21])
{
	state_transitions.push(function(wentBackwards)
	{
		highlightTreeForSources(new Set(path.slice(0, endState)), sortedContext)
		s.refresh()
	})
}

state_transitions.push(function(wentBackwards)
{
	highlightTreeForSources(new Set(path), sortedContext, "the$")
	s.refresh()
})

state_transitions.push(function() {})
state_transitions.push(function(wentBackwards) {
	// Further Improvement

	// for (const node of decomposedNodes) // we set these because it affects auto-zoom
	// {
	// 	node.x = node.decomposed_x
	// 	node.y = node.decomposed_y
	// }

	if (wentBackwards)
	{
		for (const node of nonDecomposedNodes) {
			node.x = node.LCRS_x
			node.y = node.LCRS_y
		}

		highlightTreeForSources(new Set(path), sortedContext, "the$")
		filter
			.undo("decomposedEdges")
			.edgesBy(isSortedEdge, "sortedEdges")
			.undo("decomposedNodes")
			.nodesBy(isNonDecomposedNode, "nonDecomposedNodes")
			.apply()

		defaultEdgeLabelSize += 3
		resize()
	}
	s.refresh()
})

state_transitions.push(function(wentBackwards)
{ //The Dynamic Decomposed Trie
	if (!wentBackwards)
	{
		for (const node of s.graph.nodes())
			node.color = ORIGINAL_COLOR

		resetGraph(sortedContext)
		filter
			.undo("sortedEdges")
			.edgesBy(isDecomposedEdge, "decomposedEdges")
			.undo("nonDecomposedNodes")
			.nodesBy(isDecomposedNode, "decomposedNodes")
			.apply()


		for (const node of decomposedNodes)
		{
			// node.x = node.LCRS_x
			// node.forceLabel = 9
			node.color = ORIGINAL_COLOR
		}

		for (const edge of decomposedEdges)
		{
			edge.doNotBack = edge.source !== "d_[ROOT]$"
			edge.active_color = SELECTED_COLOR
		}

		defaultEdgeLabelSize -= 3
		resize()

		for (const node of recomposedNodes)
		{
			node.color = ORIGINAL_COLOR
		}

		for (const edge of recomposedEdges)
		{
			edge.active = true
			edge.active_color = ORIGINAL_COLOR
		}
	}
	// else
	{
		sigma.plugins.animate(
			s,
			{
				x: "LCRS_x",
				y: "LCRS_y",
			},
			{
				nodes: decomposedNodes,
				// easing: 'cubicInOut',
				duration: wentBackwards ? undefined : 1,
				// onComplete: function() {}
			}
		);

		setTimeout(function()
		{
			sigma.plugins.animate(
				s,
				{
					x: "LCRS_x",
					y: "LCRS_y",
				},
				{
					nodes: decomposedNodes,
					// easing: 'cubicInOut',
					duration: wentBackwards ? undefined : 1,
					// onComplete: function() {}
				}
			);
		}, WAIT_TIME)
	}
})

state_transitions.push(function(wentBackwards)
{ //Sorting The Dynamic Decomposed Trie vertically
	if (wentBackwards)
	{
		filter
			.undo("sortedDecomposedEdges")
			.edgesBy(isDecomposedEdge, "decomposedEdges")
			.apply()

		for (const edge of decomposedEdges)
			if (edge.flipMe)
				edge.targetLabel ^= 7;
	}
	// else
	{
		decomposedEdges.find(edge => edge.target === "d_listings$").targetLabel = 3
		setTimeout(function()
		{
			sigma.plugins.animate(
				s,
				{
					x: "LCRS_x",
					y: "decomposed_y",
				},
				{
					nodes: decomposedNodes,
					// easing: 'cubicInOut',
					// duration: 2000,
					// onComplete: function() {}
				}
			);


		}, WAIT_TIME)
	}

	s.refresh()
})

state_transitions.push(function(wentBackwards) {
	// Moving DynSDT to LCRS
	if (!wentBackwards) {
		filter
			.undo("decomposedEdges")
			.edgesBy(isRecomposedEdge, "sortedDecomposedEdges")
			.apply()

		for (const edge of decomposedEdges)
			if (edge.flipMe)
				edge.targetLabel ^= 7;
	}

	decomposedEdges.find(edge => edge.target === "d_listings$").targetLabel = 4
	setTimeout(function()
	{
		sigma.plugins.animate(
			s,
			{
				x: "decomposed_x",
				y: "decomposed_y",
				// size: prefix + 'size',
				// color: prefix + 'color'
			},
			{
				nodes: decomposedNodes,
				// easing: 'cubicInOut',
				// duration: 2000,
				// onComplete: function() {
				// 	// do stuff here after animation is
				// 	for (const edge of decomposedEdges)
				// 	{
				// 		// if (edge.target === "d_listings$")
				// 		// 	edge.targetLabel = 4
				// 		// else if (edge.target === "d_listed$")
				// 		// 	edge.targetLabel = 3
				// 		// else
				// 		if (edge.target === "d_list of$")
				// 		{
				// 			// edge.targetLabel = 4
				// 			// edge.type = "arrow"
				// 		}
				// 		// else if (edge.target === "d_list$")
				// 		// 	edge.targetLabel = 6
				// 		// else if (edge.target === "d_of$")
				// 		// 	edge.type = "curvedArrow"
				// 	}
				// 	s.refresh()
				// }
			}
		);
	}, WAIT_TIME)

	// if (wentBackwards)
	{
		for (const node of recomposedNodes)
		{
			node.color = ORIGINAL_COLOR
			node.forceLabel = 0
		}

		for (const edge of recomposedEdges)
		{
			edge.active = true
			edge.active_color = ORIGINAL_COLOR
		}

		recomposedRoot.forceLabel = RECOMPOSED_ROOT_LABEL
	}

	s.refresh()
})

// state_transitions.push(function() {
// 	root.color = PICKED_COLOR
// 	list_node.color = SELECTED_COLOR

// 	for (const edge of recomposedEdges)
// 	{
// 		edge.active = true
// 		edge.active_color = edge.target === "d_list$" ? SELECTED_COLOR : ORIGINAL_COLOR
// 	}

// 	s.refresh()
// })

// state_transitions.push(function() {
// 	root.color = PICKED_COLOR
// 	list_node.color = PICKED_COLOR

// 	for (const edge of recomposedEdges)
// 	{
// 		edge.active = true
// 		edge.active_color = edge.source === "d_list$" ? SELECTED_COLOR :
// 			(edge.target === "d_list$" ? PICKED_COLOR : ORIGINAL_COLOR)
// 	}

// 	s.refresh()
// })
const forceLabels = new Map([
	["d_line$", 6],
	["d_lisa$", 6],
	["d_list a$", 6],

	["d_list of$", 10],
	["d_listings$", 10],
	["d_little$", 9], //
	["d_life$", 7], //
	["d_lise$", 7], //
	["d_listed$", 9],
	["d_lisbon$", 9],

	["d_world$", 6],
	["d_league$", 6],
	["d_of$", 6],
	["d_the$", 10],
])

{
	const root = recomposedNodes.find(node => node.isRoot)
	const list_node = recomposedNodes.find(node => node.id === "d_list$")
	const pickedEdgesAccumulator = []
	const selectedEdgesAccumulator = []
	const seenStrs = new Set()
	const arr = ["d_wikipedia$", "d_list$", "d_list of$", "d_of$", "d_the$"]

	for (let i = 0, length = arr.length; i < length; i++)
	{
		const str = arr[i]
		seenStrs.add(str)

		for (const edge of recomposedEdges)
		{
			if (edge.target === str)
			{
				pickedEdgesAccumulator.push(edge)
			}
		}

		const pickedEdges = [...pickedEdgesAccumulator]

		const pickedNodes = recomposedNodes.filter(node => pickedEdges.find(edge => edge.target === node.id))

		if (i !== length - 1)
			for (const edge of recomposedEdges)
				if (edge.source === str)
					selectedEdgesAccumulator.push(edge)

		const selectedEdges = [...selectedEdgesAccumulator]
		const selectedNodes = recomposedNodes.filter(node => selectedEdges.find(edge => edge.target === node.id))

		if (i)
		state_transitions.push(function() {
			root.color = PICKED_COLOR
			list_node.color = PICKED_COLOR

			for (const node of recomposedNodes)
			{
				node.color = DISABLED_COLOR
				node.forceLabel = 0
			}

			for (const edge of recomposedEdges)
			{
				edge.active = true
				edge.active_color = DISABLED_COLOR
			}

			for (const edge of selectedEdges)
				edge.active_color = SELECTED_COLOR

			for (const node of selectedNodes)
			{
				node.color = SELECTED_COLOR
				node.forceLabel = forceLabels.get(node.id)
			}

			for (const edge of pickedEdges)
				edge.active_color = PICKED_COLOR

			for (const node of pickedNodes)
			{
				node.color = PICKED_COLOR
				node.forceLabel = 0
			}

			recomposedRoot.forceLabel = RECOMPOSED_ROOT_LABEL
			s.refresh()
		})
	}
}


const list_node = recomposedNodes.find(node => node.id === "d_list$")

state_transitions.push(function() {
	for (const node of recomposedNodes)
	{
		node.color = ORIGINAL_COLOR
		node.forceLabel = 0
	}

	recomposedRoot.forceLabel = RECOMPOSED_ROOT_LABEL

	for (const edge of recomposedEdges)
	{
		edge.active = true
		edge.active_color = ORIGINAL_COLOR
	}

	list_node.size = NODE_SIZE

	s.refresh()
})

{
	const pickedEdgesAccumulator = []
	const selectedEdgesAccumulator = []
	const traversedEdgesAccumulator = []
	const seenStrs = new Set()
	const arr = ["d_wikipedia$", "d_list$", "d_list of$", "d_line$", "d_little$", "d_life$", "d_listings$", "d_listed$", "d_lisa$", "d_lisbon$", "d_lise$"]

	for (let i = 0, length = arr.length; i < length; i++)
	{
		const str = arr[i]
		seenStrs.add(str)

		for (const edge of recomposedEdges)
		{
			if (edge.target === str)
			{
				pickedEdgesAccumulator.push(edge)
			}
		}

		const pickedEdges = [...pickedEdgesAccumulator]
		const pickedNodes = recomposedNodes.filter(node => pickedEdges.find(edge => edge.target === node.id))

		if (i !== length - 1)
			for (let edge of recomposedEdges)
				if (edge.source === str)
				{
					if (!edge.target.startsWith("d_li"))
					{
						// Find node which does start with d_li
						// pickedEdgesAccumulator.push(edge)
						const path = []
						do
						{
							path.push(edge)
							const target = edge.target
							edge = recomposedEdges.find(edge => edge.type === "dashedArrow" && edge.source === target)
						} while (edge !== undefined && !edge.target.startsWith("d_li"))

						if (edge !== undefined)
						{
							console.log(edge.target)
							traversedEdgesAccumulator.push(...path)
							selectedEdgesAccumulator.push(edge)
						}
					}
					else if (edge.target !== "d_list of$")
						selectedEdgesAccumulator.push(edge)
				}


		const traversedEdges = [...traversedEdgesAccumulator]
		const traversedNodes = recomposedNodes.filter(node => traversedEdgesAccumulator.find(edge => edge.target === node.id))

		// console.log({traversedEdges, traversedNodes})
		const selectedEdges = [...selectedEdgesAccumulator]
		const selectedNodes = recomposedNodes.filter(node => selectedEdges.find(edge => edge.target === node.id))

		if (i)
		state_transitions.push(function() {
			// list_node.size = 10

			for (const node of recomposedNodes)
			{
				node.color = DISABLED_COLOR
				node.forceLabel = 0
			}

			for (const edge of recomposedEdges)
			{
				edge.active = true
				edge.active_color = DISABLED_COLOR
			}

			for (const edge of selectedEdges)
				edge.active_color = SELECTED_COLOR

			for (const node of selectedNodes)
			{
				node.color = SELECTED_COLOR
				node.forceLabel = forceLabels.get(node.id)
			}

			for (const edge of pickedEdges)
				edge.active_color = PICKED_COLOR

			for (const node of pickedNodes)
			{
				node.color = PICKED_COLOR
				node.forceLabel = 0
			}

			for (const edge of traversedEdges)
				edge.active_color = TRAVERSED_COLOR

			for (const node of traversedNodes)
				node.color = TRAVERSED_COLOR


			recomposedRoot.forceLabel = RECOMPOSED_ROOT_LABEL
			s.refresh()
		})
	}
}

// for (const edge of decomposedEdges)
// {
// 	if (edge.target === "d_listings$")
// 	{
// 		edge.targetLabel = 4
// 	}
// 	if (edge.target === "d_listed$")
// 	{
// 		edge.targetLabel = 3
// 	}
// 	if (edge.target === "d_list of$")
// 	{
// 		edge.targetLabel = 5
// 		// edge.type = "curvedArrow"
// 	}
// }

let pane_state = 0;

function previousPane()
{
	if (pane_state !== 0)
	{
		controlPanes[pane_state].setAttribute("hidden", '')
		pane_state -= 1
		window.location.href = "#" + pane_state
		controlPanes[pane_state].removeAttribute("hidden")
		state_transitions[pane_state](true)
	}
}

function nextPane()
{
	if (pane_state !== controlPanes.length - 1)
	{
		controlPanes[pane_state].setAttribute("hidden", '')
		pane_state += 1
		window.location.href = "#" + pane_state
		controlPanes[pane_state].removeAttribute("hidden")
		state_transitions[pane_state](false)
	}
}

window.onhashchange = function() {
    const targetState = getStateFromURL()

	while (pane_state !== targetState)
	{
		if (pane_state > targetState)
			previousPane()
		else
			nextPane()
	}
};

for (let i = 0, last = controlPanes.length - 1; i <= last; i++)
{
	if (i !== 0)
		controlPanes[i].insertAdjacentElement("beforeend", createButton("left", previousPane))


	if (i !== last)
	{
		state_transitions[i + 1] ||= function() {}

		controlPanes[i].insertAdjacentElement("beforeend", createButton("right", nextPane))

		if (START_STATE > i)
			nextPane()
	}

	if (i !== 0) {
		controlPanes[i].insertAdjacentElement("beforeend", createMinimize(() => {
			for (let j = 0; j < controlPanes.length; j++) {
				if (controlPanes[j].classList.contains("minimized-control-pane")) {
					controlPanes[j].classList.remove("minimized-control-pane")
				} else {
					controlPanes[j].classList.add("minimized-control-pane")
				}
			}
		}));
	}
}
window.addEventListener("keydown", function (event) {
	if (event.defaultPrevented) {
	  return; // Do nothing if the event was already processed
	}

	switch (event.key) {
	  case "ArrowLeft":
		previousPane();
		break;
	  case "ArrowRight":
		nextPane();
		break;
	  default:
		return; // Quit when this doesn't handle the key event.
	}

	// Cancel the default action to avoid it being handled twice
	event.preventDefault();
  }, true);

setTimeout(function() {
	WAIT_TIME = 500
	s.settings("animationsTime", 5000)
}, 100)
// for (let i = 0, prev = document.getElementById("cp0"), cur; cur = document.getElementById("cp" + (i + 1)); i++, prev = cur) {
// 	state_changers[i + 1] ||= function() {}

// 	document.getElementById("left" + (i + 1)).onclick = (function() {
// 		state_changers[i](i + 1)
// 		s.refresh()
// 		cur.hidden = true;
// 		prev.hidden = false;
// 	})

// 	const f = document.getElementById("right" + i).onclick = (function() {
// 		state_changers[i + 1](i)
// 		s.refresh()
// 		prev.hidden = true;
// 		cur.hidden = false;
// 	});

// 	if (START_STATE > i) f();
// 	if (REMOVE_DIALOG) cur.hidden = true;
// }
// { id: , , x: 0, y: 262144, size: 1220297 },
// let id = 0;

// for (const edge of root_subtree.edges) {
// 	edge.active_color = SELECTED_COLOR
// }

// for (const node of root_subtree.nodes) {
// 	node.color = SELECTED_COLOR
// }

// let id = 0;
// const newEdge = s.graph.addEdge(
// 	{ source: `[ROOT]`, target: `list of$`, id: `_${id++}`, label: `wikipedia`, type: `arrow` }
// )

// newEdge.edgeActiveColor = "edge"
// newedge.size = 12000000000000

// s.graph.addNode({
// 	id: `decomposed_wikipedia$`,
// 	label: `"wikipedia$":1220297`

// 	size: nodeRadius,
// 	x: x + Math.random() / 10,
// 	y: y + Math.random() / 10,
// 	dX: 0,
// 	dY: 0,
// 	type: 'goo'
// });

// document.getElementById("right1").disabled = true;
// s.bind("overNode", function(event) {
// 	numHovers++;
// 	if (numHovers > 1)
// 		document.getElementById("right1").disabled = false;
// })

// var force = false;
// document.getElementById('layout').onclick = function() {
//	 if (!force)
// s.startForceAtlas2({slowDown: 10});
//	 else
// 	sig.stopForceAtlas2();
//	 force = !force;
// };

// Initialize the dragNodes plugin:
// var dragListener = sigma.plugins.dragNodes(s, s.renderers[0]);

// dragListener.bind('startdrag', function(event) {
// //   console.log(event);
// });
// dragListener.bind('drag', function(event) {
// //   console.log(event);
// });
// dragListener.bind('drop', function(event) {
// //   console.log(event);
// });
// dragListener.bind('dragend', function(event) {
// //   console.log(event);
// });

// var t = sigma
// for (k in t) console.log(k, t[k])
// getSerializedSvg()


setTimeout(function() {
	for (const k in fakeContexts) {
		if (k === "scene")
		{
			console.log(fakeContexts[k].getSerializedSvg())
		}
	}
}, 5000);

// var dragListener = sigma.plugins.dragNodes(s, s.renderers[0]);

// dragListener.bind('startdrag', function(event) {
//   console.log(event);
// });
// dragListener.bind('drag', function(event) {
//   console.log(event);
// });
// dragListener.bind('drop', function(event) {
//   console.log(event);
// });
// dragListener.bind('dragend', function(event) {
//   console.log(event);
// });

function resize() {
	var h = this.window.innerHeight
	var w = this.window.innerWidth
	// console.log({h,w})

	// this.setTimeout(function() {

	// 	var h = this.window.innerHeight
	// 	var w = this.window.innerWidth
	// 	console.log(':',{h,w})
	// }, 500)

	var r = w / 2560
	s.settings("minEdgeSize", r*2.5)
	s.settings("maxEdgeSize", r*2.5)

	s.settings("minNodeSize", r*7 )
	s.settings("maxNodeSize", r*7 )
	// minNodeSize: 7,
	// maxNodeSize: 7,
	const fontSize = Math.max(16, Math.min(28, r * 28 * 1.25))
	const defaultEdgeLabelSize2 = Math.max(16, Math.min(defaultEdgeLabelSize, r * defaultEdgeLabelSize * 1.25))
	s.settings("defaultLabelSize", fontSize)
	s.settings("defaultEdgeLabelSize", defaultEdgeLabelSize2)
	s.refresh();
}

window.onresize = resize;
resize();
