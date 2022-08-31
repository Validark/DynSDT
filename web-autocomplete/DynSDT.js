"use strict";
const NULL = 2 ** 16 - 1;
function normalizeString(str) {
    // this could be normalized more by, e.g. removing accents/diacritics and such.
    return str.toLocaleLowerCase();
}
function generateTerms(contacts) {
    const terms = new Array(contacts.length * 3);
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
function sortContactsIfUnsorted(contacts) {
    let previous = Infinity;
    for (const { timestamp } of contacts) {
        if (previous < timestamp)
            return contacts.sort((a, b) => b.timestamp - a.timestamp);
        previous = timestamp;
    }
    return contacts;
}
class DynSDT {
    constructor(contacts) {
        this.root = 0;
        this.availableSlots = DynSDT.OVER_ALLOCATE_BY;
        this.contacts = sortContactsIfUnsorted(contacts);
        const terms = this.terms = generateTerms(contacts);
        this.nodes = new Uint16Array(3 * (terms.length + this.availableSlots));
        for (let j = 0, { length } = terms; j < length; j++) {
            this.setDown(j, NULL);
            this.setNext(j, NULL);
            if (j === 0)
                continue;
            const term = terms[j];
            let LCP = 0;
            let node = 0;
            DESCEND_DEEPER: while (true) {
                for ( // Calculate Longest Common Prefix between `node.term` and `term`
                let key = terms[node], len = Math.min(term.length, key.length); LCP < len && term[LCP] === key[LCP]; LCP++)
                    ;
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
    async saveToCache(cacheName) {
        return caches.open(cacheName)
            .then(cache => {
            return Promise.all([
                cache.put("/structure", new Response(this.nodes)),
                cache.put("/emails", new Response(this.contacts
                    .map(e => `${e.first_name},${e.last_name},${e.email},${e.timestamp}`)
                    .join()))
            ]);
        });
    }
    static async fromCache(cacheName, contacts) {
        const cacheOpened = caches.open(cacheName);
        const contactsPromise = contacts !== null && contacts !== void 0 ? contacts : cacheOpened
            .then(cache => cache.match("/emails"))
            .then(data => data === null || data === void 0 ? void 0 : data.text())
            .then(text => {
            if (text === undefined)
                return;
            const objects = text.split(',');
            const length = (objects.length / 4) | 0;
            const contacts = new Array(length);
            let j = 0;
            for (let i = 0; i < length; i++, j += 4) {
                contacts[i] = {
                    first_name: objects[j],
                    last_name: objects[j + 1],
                    email: objects[j + 2],
                    timestamp: +objects[j + 3],
                };
            }
            return contacts;
        });
        const cache = await cacheOpened
            .then(cache => cache.match("/structure"))
            .then(data => data === null || data === void 0 ? void 0 : data.arrayBuffer())
            .then(buffer => buffer && new Uint16Array(buffer));
        contacts = await contactsPromise;
        if (contacts === undefined)
            return undefined;
        if (cache === undefined)
            return new DynSDT(contacts);
        const self = Object.create(DynSDT.prototype);
        self.contacts = contacts;
        // This is (often) the heaviest part of this function.
        // We *could* cache this too, but it would be a lot of data without much actual time savings
        self.terms = generateTerms(contacts);
        let i = cache.length;
        for (; i > 0; --i)
            if (cache[i - 1] !== 0)
                break;
        // i points to the last 0 (else it's the length);
        // calculate how many 0's were at the end, divided by 3 to get how many nodes could be stored
        self.availableSlots = (cache.length - i) / 3 | 0;
        self.nodes = cache;
        self.root = 0; // TODO:
        return self;
    }
    saveToLocalStorage(cacheName) {
        // convert to Int16Array because we use 2**16-1 to be our "null pointer", which is 65535
        // `65535` is 5 characters, whereas `-1` is 2 characters :)
        window.localStorage.setItem(cacheName + "_DynSDT", new Int16Array(this.nodes));
        window.localStorage.setItem(cacheName, this.contacts
            .map(e => `${e.first_name},${e.last_name},${e.email},${e.timestamp}`)
            .join());
    }
    /** Takes in a string `key` to access inside window.localStorage.
     * localStorage.getItem(key + "_DynSDT") -> where the data structure is stored.
     * localStorage.getItem(key) -> where the contacts are stored.
     * `contacts` can optionally be passed in instead of being read from the cache.
     */
    static fromLocalStorage(cacheName, contacts) {
        if (contacts === undefined) {
            const contactsCache = window.localStorage.getItem(cacheName);
            if (contactsCache === null)
                return undefined;
            const objects = contactsCache.split(',');
            const length = (objects.length / 4) | 0;
            contacts = new Array(length);
            let j = 0;
            for (let i = 0; i < length; i++, j += 4) {
                contacts[i] = {
                    first_name: objects[j],
                    last_name: objects[j + 1],
                    email: objects[j + 2],
                    timestamp: +objects[j + 3],
                };
            }
        }
        if (contacts === undefined)
            return undefined;
        const cache = window.localStorage.getItem(cacheName + "_DynSDT");
        if (cache === null)
            return new DynSDT(contacts);
        const self = Object.create(DynSDT.prototype);
        self.contacts = contacts;
        // This is (often) the heaviest part of this function.
        // We *could* cache this too, but it would be a lot of data without much actual time savings
        self.terms = generateTerms(contacts);
        const uncompressedArray = JSON.parse(`[${cache}]`);
        let i = uncompressedArray.length;
        for (; i > 0; --i)
            if (uncompressedArray[i - 1] !== 0)
                break;
        // i points to the last 0 (else it's the length);
        // calculate how many 0's were at the end, divided by 3 to get how many nodes could be stored
        const availableSlots = (uncompressedArray.length - i) / 3 | 0;
        uncompressedArray.length += this.OVER_ALLOCATE_BY - availableSlots;
        self.availableSlots = this.OVER_ALLOCATE_BY;
        self.nodes = new Uint16Array(uncompressedArray);
        self.root = 0; // TODO:
        return self;
    }
    getNext(node) { return this.nodes[node * 3 + 2]; }
    setNext(node, next) { return this.nodes[node * 3 + 2] = next; }
    getDown(node) { return this.nodes[node * 3 + 1]; }
    setDown(node, down) { return this.nodes[node * 3 + 1] = down; }
    getLCP(node) { return this.nodes[node * 3]; }
    setLCP(node, next) { return this.nodes[node * 3] = next; }
    getScore(node) { return this.contacts[(node / 3) | 0].timestamp; }
    getContactNode(node) { return this.contacts[(node / 3) | 0]; }
    getNodeData(node) {
        if (node === NULL)
            return { term: null, score: null, LCP: null, down: null, next: null };
        return {
            term: this.terms[node],
            score: this.getScore(node),
            LCP: this.getLCP(node),
            down: this.getDown(node) !== NULL && this.getNodeData(this.getDown(node)),
            next: this.getNext(node) !== NULL && this.getNodeData(this.getNext(node))
        };
    }
    GetLocusForPrefix(prefix, node = this.root, LCP = 0) {
        const prefixLength = prefix.length;
        if (node === NULL)
            return NULL;
        while (true) {
            for (let term = this.terms[node], l = Math.min(prefixLength, term.length); LCP < l && prefix[LCP] === term[LCP]; LCP++)
                ;
            if (LCP === prefixLength)
                return node;
            node = this.getNext(node);
            while (true) {
                if (node === NULL)
                    return NULL;
                if (this.getLCP(node) === LCP)
                    break;
                node = this.getDown(node);
            }
        }
    }
    GetTopKForPrefix(prefix, topK, node = this.GetLocusForPrefix(prefix), blacklist = []) {
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
                        len = this.topKAddSuccessiveNodes(prefixLength, results[i], results, len, set);
                    }
                    break;
                }
            }
        }
        const realResults = new Array(len);
        for (let i = 0; i < len; i++)
            realResults[i] = this.getContactNode(results[i]);
        return realResults;
    }
    topKAddSuccessiveNodes(prefixLength, node, results, len, set) {
        {
            const next = this.getNext(node);
            if (next !== NULL)
                len = this.topKAdd(prefixLength, next, results, len, set);
        }
        while ((node = this.getDown(node)) !== NULL) {
            if (this.getLCP(node) < prefixLength)
                continue;
            len = this.topKAdd(prefixLength, node, results, len, set);
            break;
        }
        return len;
    }
    topKAdd(prefixLength, node, results, len, set) {
        const score = this.getScore(node);
        const isFull = len === results.length; // if we are full and node.score is lower than the minimum, return
        if (isFull && score <= this.getScore(results[len - 1]))
            return len;
        const { size } = set;
        set.add(this.getContactNode(node));
        if (size === set.size)
            return this.topKAddSuccessiveNodes(prefixLength, node, results, len, set); // if `node` already existed, grab its successors instead
        let i = len - +isFull; // When full, plan on inserting in the last index, otherwise insert in the next index
        for (; score > this.getScore(results[i - 1]); --i)
            results[i] = results[i - 1]; // shift elements as needed to maintain descending order (by score)
        results[i] = node;
        return len + 1 - +isFull;
    }
}
/** Overallocate by this many slots during initialization to allow for growth without having to resize */
DynSDT.OVER_ALLOCATE_BY = 20;
