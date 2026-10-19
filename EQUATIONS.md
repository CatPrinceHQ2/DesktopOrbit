# Equation input

Enter an equation in the widget's equation field and press **Apply**. Custom expressions use the graph form `y = f(x)`, with `x` measured in units of half the monitor's logical height. The graph is sampled across the screen width and clipped to the visible top and bottom edges.

Examples:

```text
y = 2x
y = -0.5x + 1
y = 2sin(3x)
y = cos(x) + sin(2x)
y = tan(x)
y = sqrt(abs(x))
```

Multiplication may be explicit (`2*x`) or implicit (`2x`, `3sin(x)`, `2(x+1)`). Use radians for trigonometric functions.

Supported functions:

- Trigonometric: `sin`, `cos`, `tan`, `sec`, `csc`, `cot`.
- Inverse trigonometric: `asin`, `acos`, `atan`, `arcsin`, `arccos`, `arctan`, `atan2`.
- Hyperbolic: `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`.
- Other: `sqrt`, `abs`, `exp`, `ln`, `log`, `log10`, `floor`, `ceil`, `round`, `sign`, `min`, `max`, and `pow`.
- Constants: `pi`, `tau`, and `e`.

Available operators are `+`, `-`, `*`, `/`, and `^`; parentheses control grouping. This custom parser handles explicit `y=f(x)` functions. The built-in circle remains available for a closed curve; general implicit equations such as `x^2 + y^2 = 1` are not parsed as custom functions.
