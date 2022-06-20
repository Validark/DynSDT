const map = new Map([
    ["", ``],
    ["theta", `<span class="theta">\u{3B8}</span>`],
    ["Theta", `<span class="theta">Θ</span>`],
    ["Otilde", `<span class="big-O">Õ</span>`],
    ["Omega", `<span class="theta">Ω</span>`],
    ["O", `<span class="big-O">O</span>`],
    ["o", `<span class="big-O">o</span>`],
])

function matchWhitespace(str, i) {
	let done
	do {
		done = true
		switch(str[i]) {
			case ' ':
			case '\t':
			case '\n':
			case '\r':
				i++
				done = false;
		}
	} while (!done)
	return i
}

function parse(rest, i, pair, disallowLog) {
	var newStr = pair[0]
	i = matchWhitespace(rest, i)

	while (!rest.startsWith(pair[1], i)) {
		if (!disallowLog && rest.startsWith("log", i)) {
			i += 3
			newStr += "log"
		} else if (!disallowLog && rest.startsWith("|", i)) {
			const ret = parse(rest, i + 1, "||", true)
			i = ret.i
			newStr += `<span class="l|">|</span>`
			// newStr += `<span class="VeryThinSpace"></span>`
			newStr += ret.newStr.slice(1, -1);
			// newStr += `<span class="VeryThinSpace"></span>`
			newStr += `<span class="r|">|</span>`
		} else if (!disallowLog && rest.startsWith("(", i)) {
			const ret = parse(rest, i + 1, "()")
			i = ret.i
			newStr += `(`
			// newStr += `<span class="VeryThinSpace"></span>`
			newStr += ret.newStr.slice(1, -1);
			// newStr += `<span class="VeryThinSpace"></span>`
			newStr += `)`
		} else if (rest.startsWith("Sigma", i)) {
			i += 5
			newStr += "Σ"
		// } else if (rest.startsWith("/", i)) {
			// i += 1
			// newStr += `<span style="font-family: serif; font-size: 130%; vertical-align: -8%">÷</span>`
			// newStr += `÷`

		} else if (/\d/.test(rest[i])) {
			newStr += rest[i]
			i += 1
		} else {
			var escaped = rest.slice(i).match(/^&\w+;/)
			if (escaped)
			{
				newStr += `<span style="font-family: serif">${escaped[0]}</span>`
				// newStr += escaped[0]
				i += escaped[0].length
			}
			else
			{
				var invisible = 0

				if (rest.startsWith("_", i)) {
					invisible = ++i
				}

				const cuFirst = rest.charCodeAt(i);
				const nextIndex = i + 1;

				if ( // Check if it’s the start of a surrogate pair.
					cuFirst >= 0xD800 && cuFirst <= 0xDBFF && // high surrogate
					size > nextIndex // there is a next code unit
				) {
					const cuSecond = rest.charCodeAt(nextIndex);
					if (cuSecond >= 0xDC00 && cuSecond <= 0xDFFF) { // low surrogate
						nextIndex += 1
					}
				}

				if (invisible) {
					newStr += `<var><span class="invisible" data-str="${rest.slice(i, nextIndex)}"></span></var>`
				}
				else {
					newStr += `<var>${rest.slice(i, nextIndex)}</var>`
				}
				i = nextIndex
			}
		}



		if (rest.startsWith(pair[1], i)) break
		var tmp

		if (/^\s*[+]\s*/.test(rest.slice(i))) {
			// newStr += rest[i]
			newStr += `<span class="ThickSpace"></span><span class="ThickSpace"></span><span class="plus">${rest[i+1]}</span><span class="ThickSpace"></span><span class="ThickSpace"></span>`
			i += 3
			i = matchWhitespace(rest, i)
		}
		else if (/^\s*[-\/]\s*/.test(rest.slice(i))) {
			// newStr += rest[i]
			newStr += `&nbsp;<span style="font-family: serif">${rest[i+1] === "/" ? "÷" : rest[i+1]}</span>&nbsp;`
			i += 3
			i = matchWhitespace(rest, i)
		} else if (i !== (tmp = matchWhitespace(rest, i))) {
			i = tmp;
			newStr += `<span class="ThinSpace"></span>`
		}
		{
			// newStr += `<span class="VeryThinSpace"></span>`
		}

	}

	return { newStr: newStr + pair[1], i: i + 1 }
}

function formatComplexity(exp) {
	const found = exp.match(/^(?:[tT]heta|Omega|Otilde|O|o)/)
	const symbol = found ? found[0] : ""
	let rest = exp.slice(symbol.length)

	const open = rest.startsWith("(")
	const close = rest.endsWith(")")

	if (!open || !close) {
		rest = `(${rest})`
	}

	let ret = map.get(symbol) + parse(rest, 1, "()").newStr

	if (!open || !close) {
		ret = ret.slice(1, -1)
	}

	return ret
}

// console.log(formatComplexity(`log(|x| +
// 	1)`))

// module.exports = formatComplexity
