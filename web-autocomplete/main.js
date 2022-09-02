"use strict";
(async () => {
    // window.localStorage.clear();
    // for (const key of await caches.keys())
    // 	caches.delete(key);
    const TOP_K = 10;
    const DynSDT_CACHE = "DynSDT_Cache";
    console.time("Getting 10k emails and pre-built structure from local storage");
    let tree = DynSDT.fromLocalStorage(DynSDT_CACHE); // we have to abuse the nonNull assertion operator here so that functions which capture this variable rightfully assume it is always defined for their usage.
    if (tree === undefined) {
        console.time("Building tree from scratch with 10k emails. Please refresh the page to see how long it takes to load from localStorage/caches!");
        tree = new DynSDT(EMAIL_DATA);
        console.timeEnd("Building tree from scratch with 10k emails. Please refresh the page to see how long it takes to load from localStorage/caches!");
    }
    else
        console.timeEnd("Getting 10k emails and pre-built structure from local storage");
    console.time("Save data structure and 10k emails to local storage");
    tree.saveToLocalStorage(DynSDT_CACHE);
    console.timeEnd("Save data structure and 10k emails to local storage");
    console.log("");
    console.time("Getting 10k emails and pre-built structure from cache");
    if ((await DynSDT.fromCache(DynSDT_CACHE)) !== undefined) {
        console.timeEnd("Getting 10k emails and pre-built structure from cache");
    }
    console.time("Save data structure and 10k emails to cache");
    await tree.saveToCache(DynSDT_CACHE);
    console.timeEnd("Save data structure and 10k emails to cache");
    for (let i = 0; i < 10; i++) // warm up :)
        tree.GetTopKForPrefix("s", TOP_K);
    const receiver_element = document.getElementsByTagName("p")[0];
    const result_list = document.getElementById("result_list");
    result_list.innerHTML = "<li></li>".repeat(TOP_K);
    const result_items = result_list.children;
    const input = document.getElementsByTagName("input")[0];
    const empty_array = new Array(); // not to be modified in place
    const receivers = new Array();
    let query_results = empty_array; // queryResults can be replaced by a new array, but cannot be modified in place
    /** We hold onto the previousLocus and previousQuery for use in subsequent queries.
     * However, because we do not store a full history, we do not support caching the results for backspace.
     * This would be pretty easy to implement, but probably less necessary anyway. Even without this optimization,
     * the code is more than fast enough.
     */
    let previous_locus = tree.root;
    let previous_query = "";
    let selected_result = 0;
    input.onfocus = function () { selected_result = 0; };
    function onInput(_) {
        let prefix = this.value;
        if (prefix) {
            prefix = prefix.trim().toLocaleLowerCase();
            if (!prefix.startsWith(previous_query)) {
                previous_locus = tree.root;
                previous_query = "";
            }
            const queryDescriptor = `topK query "${prefix}"${" ".repeat(10 - prefix.length)}`;
            console.time(queryDescriptor);
            previous_locus = tree.GetLocusForPrefix(prefix, previous_locus, previous_query.length);
            query_results = tree.GetTopKForPrefix(prefix, TOP_K, previous_locus, receivers);
            console.timeEnd(queryDescriptor);
        }
        else {
            query_results = empty_array;
            previous_locus = tree.root;
            previous_query = "";
        }
        const { length } = query_results;
        for (let i = 0; i < length; i++) {
            const completion = query_results[i];
            const item = result_items[i];
            item.innerText = `${completion.first_name} ${completion.last_name} ${completion.email}`;
            item.removeAttribute("hidden");
        }
        for (let i = length; i < result_items.length; i++) {
            result_items[i].setAttribute("hidden", "");
        }
        renderHover(selected_result = 0);
        previous_query = prefix;
    }
    ;
    input.oninput = onInput;
    onInput.call(input);
    function renderHover(i) {
        for (const item of result_items) {
            item.removeAttribute("hovered");
        }
        if (query_results.length > 0)
            result_items[i].setAttribute("hovered", "");
    }
    /** Render's the list of people to whom the email is being sent */
    function renderReceivers() {
        receiver_element.innerText = `To:${receivers.length === 0 ? "" :
            " " + receivers.map(e => e.first_name ? `${e.first_name} ${e.last_name}` : e.email).join(", ")}`;
        onInput.call(input);
    }
    /** Selects a contact as one of the receivers, and resets state */
    function selectContact(contact) {
        if (receivers.every(c => c.email !== contact.email)) {
            selected_result = 0;
            input.value = "";
            receivers.push(contact);
            renderReceivers();
        }
    }
    input.onkeydown = function (ev) {
        var _a;
        switch (ev.key) {
            /** Adds this email to the list */
            case ",":
            case "Enter": {
                ev.preventDefault();
                if (isFullyFormedEmail(this.value))
                    selectContact((_a = tree.contacts.find(c => c.email === this.value)) !== null && _a !== void 0 ? _a : { first_name: "", last_name: "", email: this.value, timestamp: 0 });
                else if (query_results.length > 0)
                    selectContact(query_results[selected_result]);
                return;
            }
            /** Removes the last contact this email is being sent to */
            case "Backspace": {
                if (input.value === "") {
                    receivers.pop();
                    renderReceivers();
                }
                return;
            }
            case " ": {
                return;
            }
            default: return;
            /** Allows one to use the arrow keys to select an item up or down in the list  */
            case "ArrowDown": {
                ev.preventDefault();
                selected_result = (selected_result + 1) % query_results.length;
                break;
            }
            case "ArrowUp": {
                ev.preventDefault();
                selected_result = ((selected_result || query_results.length) - 1);
                break;
            }
        }
        renderHover(selected_result);
    };
    for (let i = 0, { length } = result_items; i < length; i++) {
        const item = result_items[i];
        item.onclick = function (_) {
            selectContact(query_results[i]);
        };
        item.onmouseover = function (_) {
            selected_result = i;
            renderHover(selected_result);
        };
    }
    // TODO: Put a real function here that checks better.
    function isFullyFormedEmail(email) {
        let i = email.indexOf("@");
        return i !== -1 && email.includes(".", i + 1);
    }
    console.log("");
    console.log("Testing save speed:");
    for (let i = 0; i < 5; i++) {
        console.time("\tlocal storage");
        tree.saveToLocalStorage(DynSDT_CACHE);
        console.timeEnd("\tlocal storage");
        console.time("\tcache        ");
        await tree.saveToCache(DynSDT_CACHE);
        console.timeEnd("\tcache        ");
    }
    console.log("");
})();
