type BuildTupleUnchecked<T, N extends number, A extends Array<any>> = A extends { length: infer L }
	? L extends N
	? A
	: BuildTupleUnchecked<T, N, [...A, T]>
	: never;

type Digit = '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9';
/** Returns a Tuple of size N filled with T, but defaults to Array<T> if N is `number`, or negative, or a decimal. */
type BuildTuple<T, N extends number> = N extends number
	? number extends N // if the type is not a numeric literal
	? Array<T>
	: `${N}` extends `-${string}` // if the numeric literal is negative
	? Array<T>
	: `${N}` extends `${string}.${string}` // if the numeric literal is not a whole number
	? Array<T>
	: `${N}` extends `${Digit}${Digit}${Digit}${string}` // if the numeric literal is 3 digits or more
	? Array<T>
	: BuildTupleUnchecked<T, N, []> // We got a numeric literal that is a non-negative whole number, 2 digits or fewer
	: never;

type KeysAssignableTo<T, U> = { [K in keyof T]: T[K] extends U ? K : never }[keyof T];

interface Contact {
	first_name: string;
	last_name: string;
	email: string;
	timestamp: number;
}
const NULL = 2 ** 16 - 1

function normalizeString(str: string) {
	// this could be normalized more by, e.g. removing accents/diacritics and such.
	return str.toLocaleLowerCase();
}

function generateTerms(contacts: Array<Contact>) {
	const terms = new Array<string>(contacts.length * 3)
	let terms_i = 0;
	for (const object of contacts) {
		terms[terms_i++] = normalizeString(object.email);
		const first_name = normalizeString(object.first_name);
		const last_name = normalizeString(object.last_name);
		terms[terms_i++] = first_name + " " + last_name;
		terms[terms_i++] = last_name + " " + first_name;
	}
	return terms;
}

function sortContactsIfUnsorted(contacts: Array<Contact>) { // verify that contacts is sorted.
	let previous = Infinity;
	for (const { timestamp } of contacts) {
		if (previous < timestamp)
			return contacts.sort((a, b) => b.timestamp - a.timestamp);

		previous = timestamp;
	}
	return contacts;
}

function deserializeContacts(text: string) {
	const item_data: Array<string> = text.split(',');
	const { length } = item_data;
	const contacts = new Array<Contact>(length / 4);

	for (let j = 0, i = 0; j < length; ) {
		contacts[i++] = {
			first_name: item_data[j++]!,
			last_name: item_data[j++]!,
			email: item_data[j++]!,
			timestamp: +item_data[j++]!,
		};
	}
	return contacts;
}

function serializeContacts(contacts: Array<Contact>) {
	const substrs = new Array<string>(contacts.length * 4);
	let i = 0;

	for (const contact of contacts) {
		substrs[i++] = contact.first_name;
		substrs[i++] = contact.last_name;
		substrs[i++] = contact.email;
		substrs[i++] = "" + contact.timestamp;
	}

	return substrs.join()
}

class DynSDT {
	/** Overallocate by this many slots during initialization to allow for growth without having to resize */
	public static OVER_ALLOCATE_BY = 20;

	public root = 0;
	public contacts: Array<Contact>;
	public terms: Array<string>;
	public nodes: Uint16Array;
	private availableSlots: number = DynSDT.OVER_ALLOCATE_BY;

	public async saveToCache(cacheName: string) {
		return caches.open(cacheName)
			.then(cache =>
				Promise.all([
					cache.put("/structure", new Response(this.nodes)),
					cache.put("/emails", new Response(serializeContacts(this.contacts)))
				])
			);
	}

	public static async fromCache(cacheName: string) {
		return caches.open(cacheName)
			.then(cache =>
				Promise.all([
					cache.match("/emails")
						.then(data => data?.text())
						.then(text => text && deserializeContacts(text)),

					cache.match("/structure")
						.then(data => data?.arrayBuffer())
						.then(buffer => buffer && new Uint16Array(buffer))
				])
			)
			.then(([contacts, cache]) => {
				if (!contacts) return;
				if (cache === undefined) return new DynSDT(contacts);

				const self = Object.create(DynSDT.prototype) as DynSDT;
				self.contacts = contacts;

				// This is (often) the heaviest part of this function.
				// We *could* cache this too, but it would be a lot of data without much actual time savings
				self.terms = generateTerms(contacts);

				let i = cache.length
				for (; i > 0; --i) if (cache[i - 1] !== 0) break;

				// i points to the last 0 (else it's the length);
				// calculate how many 0's were at the end, divided by 3 to get how many nodes could be stored
				self.availableSlots = (cache.length - i) / 3 | 0;
				self.nodes = cache;
				self.root = 0; // TODO:
				return self;
			})
	}

	public saveToLocalStorage(cacheName: string) {
		// convert to Int16Array because we use 2**16-1 to be our "null pointer", which is 65535
		// `65535` is 5 characters, whereas `-1` is 2 characters :)
		window.localStorage.setItem(cacheName + "_DynSDT", new Int16Array(this.nodes) as never);
		window.localStorage.setItem(cacheName, serializeContacts(this.contacts));
	}

	/** Takes in a string `key` to access inside window.localStorage.
	 * localStorage.getItem(key + "_DynSDT") -> where the data structure is stored.
	 * localStorage.getItem(key) -> where the contacts are stored.
	 * `contacts` can optionally be passed in instead of being read from the cache.
	 */
	public static fromLocalStorage(cacheName: string) {
		const contactsCache = window.localStorage.getItem(cacheName);
		if (contactsCache === null) return undefined;

		const cache = window.localStorage.getItem(cacheName + "_DynSDT");
		if (cache === null) return new DynSDT(contactsCache);

		const self = Object.create(DynSDT.prototype) as DynSDT;
		const contacts = deserializeContacts(contactsCache)
		self.contacts = contacts;

		// This is (often) the heaviest part of this function.
		// We *could* cache this too, but it would be a lot of data without much actual time savings
		self.terms = generateTerms(contacts);

		const uncompressedArray = JSON.parse(`[${cache}]`) as Array<number>;
		let i = uncompressedArray.length
		for (; i > 0; --i) if (uncompressedArray[i - 1] !== 0) break;

		// i points to the last 0 (else it's the length);
		// calculate how many 0's were at the end, divided by 3 to get how many nodes could be stored
		const availableSlots = (uncompressedArray.length - i) / 3 | 0;

		uncompressedArray.length += this.OVER_ALLOCATE_BY - availableSlots;
		self.availableSlots = this.OVER_ALLOCATE_BY;

		self.nodes = new Uint16Array(uncompressedArray);
		self.root = 0; // TODO: If Set/Update methods are added, the root could be some other node
		return self;
	}

	private getNext(node: number) { return this.nodes[node * 3 + 2]!; }
	private setNext(node: number, next: number) { return this.nodes[node * 3 + 2] = next; }
	private getDown(node: number) { return this.nodes[node * 3 + 1]!; }
	private getLCP(node: number) { return this.nodes[node * 3]!; }
	private setDown(node: number, down: number) { return this.nodes[node * 3 + 1] = down; }
	private setLCP(node: number, next: number) { return this.nodes[node * 3] = next; }
	private getScore(node: number) { return this.contacts[(node / 3) | 0]!.timestamp; }
	private getContactNode(node: number) { return this.contacts[(node / 3) | 0]!; }

	public getNodeData(node: number): unknown { // this is for debugging. No need to type this
		if (node === NULL) return { term: null, score: null, LCP: null, down: null, next: null };
		return {
			term: this.terms[node],
			score: this.getScore(node),
			LCP: this.getLCP(node),
			down: this.getDown(node) !== NULL && this.getNodeData(this.getDown(node)),
			next: this.getNext(node) !== NULL && this.getNodeData(this.getNext(node))
		};
	}

	constructor(contacts: string | Array<Contact>) {
		if (typeof contacts === "string") contacts = deserializeContacts(contacts);
		this.contacts = sortContactsIfUnsorted(contacts);
		const terms = this.terms = generateTerms(contacts);
		this.nodes = new Uint16Array(3 * (terms.length + this.availableSlots));

		for (let j = 0, { length } = terms; j < length; j++) {
			this.setDown(j, NULL);
			this.setNext(j, NULL);
			if (j === 0) continue;

			const term = terms[j]!;
			let LCP = 0;
			let node = 0;

			DESCEND_DEEPER: while (true) {
				for ( // Calculate Longest Common Prefix between `node.term` and `term`
					let key = terms[node]!, len = Math.min(term.length, key.length);
					LCP < len && term[LCP] === key[LCP];
					LCP++
				);

				if (this.getNext(node) === NULL) {
					this.setLCP(j, LCP);
					this.setNext(node, j);
					break DESCEND_DEEPER;
				}

				for (node = this.getNext(node); this.getLCP(node) !== LCP; node = this.getDown(node)) {
					if (this.getDown(node) === NULL) {
						this.setLCP(j, LCP);
						this.setDown(node, j);
						break DESCEND_DEEPER;
					}
				}
			}
		}
	}

	public GetLocusForPrefix(prefix: string, previousLocus?: number | undefined, previousLCP?: number): number;
	public GetLocusForPrefix(prefix: string, node = this.root, LCP = 0) {
		const prefixLength = prefix.length;
		if (node === NULL) return NULL;
		while (true) {
			for (
				let term = this.terms[node]!, l = Math.min(prefixLength, term.length);
				LCP < l && prefix[LCP] === term[LCP];
				LCP++
			);

			if (LCP === prefixLength) return node;
			node = this.getNext(node);

			while (true) {
				if (node === NULL) return NULL;
				if (this.getLCP(node) === LCP) break;
				node = this.getDown(node);
			}
		}
	}

	/** Takes in a prefix string and finds the `topK` highest scored nodes which start with the prefix.
	 * `topK` is assumed to be a pretty small integer by this implementation, as this implements a DEPQ as an insertion sorted array rather than a Heap.
	 */
	public GetTopKForPrefix(prefix: string, topK: number, locusNode?: number | undefined, blacklist?: Array<Contact>): Array<Contact>;
	public GetTopKForPrefix(prefix: string, topK: number, node = this.GetLocusForPrefix(prefix), blacklist: Array<Contact> = []) {
		const results = new Uint16Array(topK);
		let len = 0;
		if (!(topK <= 0) && node !== NULL) {
			const set = new Set(blacklist);
			const prefixLength = prefix.length;

			const { size } = set;
			set.add(this.getContactNode(node));
			const locusIsAResult = size !== set.size;

			if (locusIsAResult) {
				results[0] = node;
				len = 1;
			}
			// technically we could break out now if topK === 1, but I am not optimizing for
			// topK == 1 because GetLocusForPrefix could have been used instead.
			for (node = this.getNext(node); node !== NULL; node = this.getDown(node)) {
				if (this.getLCP(node) >= prefixLength) {
					len = this.topKAdd(prefixLength, node, results, len, set);

					for (let i = +locusIsAResult; i < len && i < topK - 1; i++) {
						len = this.topKAddSuccessiveNodes(prefixLength, results[i]!, results, len, set);
					}

					break;
				}
			}
		}

		const realResults = new Array<Contact>(len);
		for (let i = 0; i < len; i++) realResults[i] = this.getContactNode(results[i]!);
		return realResults;
	}

	private topKAddSuccessiveNodes(prefixLength: number, node: number, results: Uint16Array, len: number, set: Set<Contact>) {
		{
			const next = this.getNext(node);
			if (next !== NULL) len = this.topKAdd(prefixLength, next, results, len, set);
		}

		while ((node = this.getDown(node)) !== NULL) {
			if (this.getLCP(node) < prefixLength) continue;
			len = this.topKAdd(prefixLength, node, results, len, set);
			break;
		}

		return len;
	}

	private topKAdd(prefixLength: number, node: number, results: Uint16Array, len: number, set: Set<Contact>) {
		const score = this.getScore(node);
		const isFull = len === results.length // if we are full and node.score is lower than the minimum, return
		if (isFull && score <= this.getScore(results[len - 1]!)) return len;
		const { size } = set;
		set.add(this.getContactNode(node));
		if (size === set.size)
			return this.topKAddSuccessiveNodes(prefixLength, node, results, len, set); // if `node` already existed, grab its successors instead

		let i = len - +isFull; // When full, plan on inserting in the last index, otherwise insert in the next index
		for (; i > 0 && score > this.getScore(results[i - 1]!); --i)
			results[i] = results[i - 1]!; // shift elements as needed to maintain descending order (by score)
		results[i] = node;
		return len + 1 - +isFull;
	}
}
