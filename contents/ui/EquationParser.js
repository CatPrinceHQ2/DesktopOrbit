.pragma library

// Safe recursive-descent parser for y=f(x). It only builds a small math AST;
// user-entered text is never passed to eval() or a JavaScript engine.
function compileY(source) {
    source = String(source).trim().toLowerCase().replace(/^y\s*=\s*/, "").replace(/\s+/g, "")
    if (!source) throw new Error("Enter an expression for y.")

    var tokenPattern = /(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?|[a-z][a-z0-9]*|[+\-*/^(),]/g
    var tokens = source.match(tokenPattern) || []
    if (tokens.join("") !== source) throw new Error("Use numbers, x, operators, parentheses, and supported function names.")
    var index = 0
    var binaryFunctions = { min: 1, max: 1, pow: 1, atan2: 1 }
    var unaryFunctions = {
        sin: 1, cos: 1, tan: 1, asin: 1, acos: 1, atan: 1,
        arcsin: 1, arccos: 1, arctan: 1, sinh: 1, cosh: 1, tanh: 1,
        asinh: 1, acosh: 1, atanh: 1, sqrt: 1, abs: 1, exp: 1,
        ln: 1, log: 1, log10: 1, floor: 1, ceil: 1, round: 1,
        sign: 1, sec: 1, csc: 1, cot: 1
    }

    function peek() { return tokens[index] || "" }
    function take() { return tokens[index++] || "" }
    function node(type, value, left, right) { return {type:type, value:value, left:left, right:right} }
    function canStartImplicit(token) { return !!token && (/^(?:\d|[a-z]|\()/.test(token)) }

    function parseExpression() {
        var left = parseTerm()
        while (peek() === "+" || peek() === "-") {
            var op = take()
            left = node("binary", op, left, parseTerm())
        }
        return left
    }
    function parseTerm() {
        var left = parseUnary()
        while (peek() === "*" || peek() === "/" || canStartImplicit(peek())) {
            var op = peek() === "*" || peek() === "/" ? take() : "*"
            left = node("binary", op, left, parseUnary())
        }
        return left
    }
    function parseUnary() {
        if (peek() === "+") { take(); return node("unary", "+", parseUnary()) }
        if (peek() === "-") { take(); return node("unary", "-", parseUnary()) }
        return parsePower()
    }
    function parsePower() {
        var left = parsePrimary()
        if (peek() === "^") { take(); return node("binary", "^", left, parseUnary()) }
        return left
    }
    function parsePrimary() {
        var token = take()
        if (!token) throw new Error("Unexpected end of expression.")
        if (token === "(") {
            var nested = parseExpression()
            if (take() !== ")") throw new Error("Missing closing parenthesis.")
            return nested
        }
        if (/^(?:\d|\.)/.test(token)) {
            var number = Number(token)
            if (!isFinite(number)) throw new Error("Invalid number.")
            return node("number", number)
        }
        if (/^[a-z][a-z0-9]*$/.test(token)) {
            if (token === "x") return node("x", "x")
            if (token === "pi") return node("number", Math.PI)
            if (token === "e") return node("number", Math.E)
            if (token === "tau") return node("number", Math.PI * 2)
            if (unaryFunctions[token] || binaryFunctions[token]) {
                if (take() !== "(") throw new Error(token + " needs parentheses, like " + token + "(x).")
                var args = [parseExpression()]
                if (peek() === ",") { take(); args.push(parseExpression()) }
                if (take() !== ")") throw new Error("Missing closing parenthesis after " + token + ".")
                if ((binaryFunctions[token] && args.length !== 2) || (unaryFunctions[token] && args.length !== 1))
                    throw new Error("Wrong number of arguments for " + token + ".")
                return {type:"function", value:token, args:args}
            }
            throw new Error("Unknown variable or function: " + token + ".")
        }
        throw new Error("Unexpected token: " + token + ".")
    }

    var ast = parseExpression()
    if (index !== tokens.length) throw new Error("Unexpected token: " + peek() + ".")

    function evaluate(current, x) {
        if (current.type === "number") return current.value
        if (current.type === "x") return x
        if (current.type === "unary") return current.value === "-" ? -evaluate(current.left, x) : evaluate(current.left, x)
        if (current.type === "binary") {
            var a = evaluate(current.left, x), b = evaluate(current.right, x)
            if (current.value === "+") return a + b
            if (current.value === "-") return a - b
            if (current.value === "*") return a * b
            if (current.value === "/") return a / b
            if (current.value === "^") return Math.pow(a, b)
        }
        if (current.type === "function") {
            var name = current.value, first = evaluate(current.args[0], x)
            if (name === "min") return Math.min(first, evaluate(current.args[1], x))
            if (name === "max") return Math.max(first, evaluate(current.args[1], x))
            if (name === "pow") return Math.pow(first, evaluate(current.args[1], x))
            if (name === "atan2") return Math.atan2(first, evaluate(current.args[1], x))
            if (name === "arcsin") name = "asin"
            if (name === "arccos") name = "acos"
            if (name === "arctan") name = "atan"
            if (name === "sec") return 1 / Math.cos(first)
            if (name === "csc") return 1 / Math.sin(first)
            if (name === "cot") return 1 / Math.tan(first)
            if (name === "ln" || name === "log") return Math.log(first)
            if (name === "log10") return Math.log(first) / Math.LN10
            if (name === "sinh") return (Math.exp(first) - Math.exp(-first)) / 2
            if (name === "cosh") return (Math.exp(first) + Math.exp(-first)) / 2
            if (name === "tanh") return (Math.exp(2 * first) - 1) / (Math.exp(2 * first) + 1)
            if (name === "asinh") return Math.log(first + Math.sqrt(first * first + 1))
            if (name === "acosh") return Math.log(first + Math.sqrt(first * first - 1))
            if (name === "atanh") return 0.5 * Math.log((1 + first) / (1 - first))
            var mathFunction = Math[name]
            if (typeof mathFunction === "function") return mathFunction(first)
        }
        return NaN
    }
    return function(x) { return evaluate(ast, x) }
}
