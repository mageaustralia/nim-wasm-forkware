## UnitCalc engine - the compiled, forkable core of this document.
##
## This is REAL Nim. In the browser it is compiled Nim -> C -> WebAssembly and
## then called live by the page. Edit the UNIT TABLE or the FORMULAS below,
## press "Recompile engine", and the calculator changes behaviour with no
## server, no toolchain install, no reload. Then "Save Fork" to pass your
## version on as a single self-contained .html.
##
## The JS shell talks to this engine through two exported functions over a
## fixed 64 KB I/O buffer (no allocation crosses the wasm boundary):
##   bufAddr(): pointer        -- address of the shared buffer
##   evalBuf(n: cint): cint    -- read n input bytes, write result, return length

import std/[math, strutils, parseutils]

type
  Dim = array[7, int]          ## exponents of the SI base units, in order:
                               ## m, kg, s, A, K, mol, cd
  Quantity = object
    val: float
    dim: Dim

func d(m, kg, s, a, k, mol, cd: int): Dim =
  [m, kg, s, a, k, mol, cd]

const Dimless: Dim = [0, 0, 0, 0, 0, 0, 0]

# ───────────────────────────────────────────────────────────────────────────
#  UNIT TABLE  -  name, factor-to-SI-base, dimension.
#  This is the obvious thing to fork: change a factor, or add a row (psi and
#  hp are here as examples), then Recompile.
# ───────────────────────────────────────────────────────────────────────────
type UnitDef = object
  name: string
  factor: float
  dim: Dim

const units: seq[UnitDef] = @[
  # length
  UnitDef(name: "m",    factor: 1.0,        dim: d(1, 0, 0, 0, 0, 0, 0)),
  UnitDef(name: "mm",   factor: 1e-3,       dim: d(1, 0, 0, 0, 0, 0, 0)),
  UnitDef(name: "cm",   factor: 1e-2,       dim: d(1, 0, 0, 0, 0, 0, 0)),
  UnitDef(name: "km",   factor: 1e3,        dim: d(1, 0, 0, 0, 0, 0, 0)),
  UnitDef(name: "in",   factor: 0.0254,     dim: d(1, 0, 0, 0, 0, 0, 0)),
  UnitDef(name: "ft",   factor: 0.3048,     dim: d(1, 0, 0, 0, 0, 0, 0)),
  # mass
  UnitDef(name: "kg",   factor: 1.0,        dim: d(0, 1, 0, 0, 0, 0, 0)),
  UnitDef(name: "g",    factor: 1e-3,       dim: d(0, 1, 0, 0, 0, 0, 0)),
  UnitDef(name: "t",    factor: 1e3,        dim: d(0, 1, 0, 0, 0, 0, 0)),
  # time
  UnitDef(name: "s",    factor: 1.0,        dim: d(0, 0, 1, 0, 0, 0, 0)),
  UnitDef(name: "ms",   factor: 1e-3,       dim: d(0, 0, 1, 0, 0, 0, 0)),
  UnitDef(name: "min",  factor: 60.0,       dim: d(0, 0, 1, 0, 0, 0, 0)),
  UnitDef(name: "h",    factor: 3600.0,     dim: d(0, 0, 1, 0, 0, 0, 0)),
  # current / temperature / amount
  UnitDef(name: "A",    factor: 1.0,        dim: d(0, 0, 0, 1, 0, 0, 0)),
  UnitDef(name: "mA",   factor: 1e-3,       dim: d(0, 0, 0, 1, 0, 0, 0)),
  UnitDef(name: "K",    factor: 1.0,        dim: d(0, 0, 0, 0, 1, 0, 0)),
  UnitDef(name: "mol",  factor: 1.0,        dim: d(0, 0, 0, 0, 0, 1, 0)),
  # force
  UnitDef(name: "N",    factor: 1.0,        dim: d(1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "kN",   factor: 1e3,        dim: d(1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "MN",   factor: 1e6,        dim: d(1, 1, -2, 0, 0, 0, 0)),
  # pressure / stress
  UnitDef(name: "Pa",   factor: 1.0,        dim: d(-1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "kPa",  factor: 1e3,        dim: d(-1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "MPa",  factor: 1e6,        dim: d(-1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "GPa",  factor: 1e9,        dim: d(-1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "bar",  factor: 1e5,        dim: d(-1, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "psi",  factor: 6894.757,   dim: d(-1, 1, -2, 0, 0, 0, 0)),
  # energy
  UnitDef(name: "J",    factor: 1.0,        dim: d(2, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "kJ",   factor: 1e3,        dim: d(2, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "MJ",   factor: 1e6,        dim: d(2, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "Wh",   factor: 3600.0,     dim: d(2, 1, -2, 0, 0, 0, 0)),
  UnitDef(name: "kWh",  factor: 3.6e6,      dim: d(2, 1, -2, 0, 0, 0, 0)),
  # power
  UnitDef(name: "W",    factor: 1.0,        dim: d(2, 1, -3, 0, 0, 0, 0)),
  UnitDef(name: "kW",   factor: 1e3,        dim: d(2, 1, -3, 0, 0, 0, 0)),
  UnitDef(name: "MW",   factor: 1e6,        dim: d(2, 1, -3, 0, 0, 0, 0)),
  UnitDef(name: "hp",   factor: 745.7,      dim: d(2, 1, -3, 0, 0, 0, 0)),
  # electrical
  UnitDef(name: "V",    factor: 1.0,        dim: d(2, 1, -3, -1, 0, 0, 0)),
  UnitDef(name: "mV",   factor: 1e-3,       dim: d(2, 1, -3, -1, 0, 0, 0)),
  UnitDef(name: "kV",   factor: 1e3,        dim: d(2, 1, -3, -1, 0, 0, 0)),
  UnitDef(name: "ohm",  factor: 1.0,        dim: d(2, 1, -3, -2, 0, 0, 0)),
  UnitDef(name: "kohm", factor: 1e3,        dim: d(2, 1, -3, -2, 0, 0, 0)),
  UnitDef(name: "Mohm", factor: 1e6,        dim: d(2, 1, -3, -2, 0, 0, 0)),
  UnitDef(name: "Hz",   factor: 1.0,        dim: d(0, 0, -1, 0, 0, 0, 0)),
  UnitDef(name: "kHz",  factor: 1e3,        dim: d(0, 0, -1, 0, 0, 0, 0)),
]

# Named constants usable in expressions.
type ConstDef = object
  name: string
  q: Quantity

const consts: seq[ConstDef] = @[
  ConstDef(name: "pi",   q: Quantity(val: PI,      dim: Dimless)),
  ConstDef(name: "e",    q: Quantity(val: E,       dim: Dimless)),
  ConstDef(name: "grav", q: Quantity(val: 9.80665, dim: d(1, 0, -2, 0, 0, 0, 0))),
]

# Preferred display name for a few common derived dimensions.
const preferred: seq[tuple[dm: Dim, name: string]] = @[
  (d(1, 1, -2, 0, 0, 0, 0),  "N"),
  (d(-1, 1, -2, 0, 0, 0, 0), "Pa"),
  (d(2, 1, -2, 0, 0, 0, 0),  "J"),
  (d(2, 1, -3, 0, 0, 0, 0),  "W"),
  (d(2, 1, -3, -1, 0, 0, 0), "V"),
  (d(2, 1, -3, -2, 0, 0, 0), "ohm"),
  (d(0, 0, 1, 1, 0, 0, 0),   "C"),
  (d(0, 0, -1, 0, 0, 0, 0),  "Hz"),
]

# ── error channel (no exceptions cross the parser; safest for wasm) ──────────
var gErr: string = ""
proc fail(msg: string) =
  if gErr.len == 0: gErr = msg

# ── dimension helpers ───────────────────────────────────────────────────────
proc addDim(a, b: Dim): Dim =
  for i in 0 .. 6: result[i] = a[i] + b[i]
proc subDim(a, b: Dim): Dim =
  for i in 0 .. 6: result[i] = a[i] - b[i]
proc mulDim(a: Dim, n: int): Dim =
  for i in 0 .. 6: result[i] = a[i] * n
proc eqDim(a, b: Dim): bool =
  for i in 0 .. 6:
    if a[i] != b[i]: return false
  true
proc isDimless(a: Dim): bool = eqDim(a, Dimless)

# ── lookups ─────────────────────────────────────────────────────────────────
proc findUnit(name: string, u: var UnitDef): bool =
  for it in units:
    if it.name == name:
      u = it
      return true
  false
proc findConst(name: string, q: var Quantity): bool =
  for it in consts:
    if it.name == name:
      q = it.q
      return true
  false

# ── quantity arithmetic ─────────────────────────────────────────────────────
proc qadd(a, b: Quantity): Quantity =
  if not eqDim(a.dim, b.dim): fail("cannot add incompatible units"); return
  Quantity(val: a.val + b.val, dim: a.dim)
proc qsub(a, b: Quantity): Quantity =
  if not eqDim(a.dim, b.dim): fail("cannot subtract incompatible units"); return
  Quantity(val: a.val - b.val, dim: a.dim)
proc qmul(a, b: Quantity): Quantity =
  Quantity(val: a.val * b.val, dim: addDim(a.dim, b.dim))
proc qdiv(a, b: Quantity): Quantity =
  if b.val == 0.0: fail("division by zero"); return
  Quantity(val: a.val / b.val, dim: subDim(a.dim, b.dim))
proc qpow(a: Quantity, n: int): Quantity =
  Quantity(val: pow(a.val, n.float), dim: mulDim(a.dim, n))

# ── functions and formulas ──────────────────────────────────────────────────
#  1-arg math functions plus multi-arg engineering formulas. Add your own
#  formula as another `of "name":` branch - that is the whole extension point.
proc qfunc(name: string, args: seq[Quantity]): Quantity =
  case name
  of "sqrt":
    if args.len != 1: fail("sqrt expects 1 argument"); return
    let a = args[0]
    var hd: Dim
    for i in 0 .. 6:
      if a.dim[i] mod 2 != 0: fail("sqrt needs even unit exponents"); return
      hd[i] = a.dim[i] div 2
    if a.val < 0.0: fail("sqrt of a negative value"); return
    return Quantity(val: sqrt(a.val), dim: hd)
  of "abs":
    if args.len != 1: fail("abs expects 1 argument"); return
    return Quantity(val: abs(args[0].val), dim: args[0].dim)
  of "sin", "cos", "tan", "asin", "acos", "atan", "exp", "ln", "log10":
    if args.len != 1: fail(name & " expects 1 argument"); return
    if not isDimless(args[0].dim): fail(name & " needs a dimensionless argument"); return
    let x = args[0].val
    var r = 0.0
    case name
    of "sin": r = sin(x)
    of "cos": r = cos(x)
    of "tan": r = tan(x)
    of "asin": r = arcsin(x)
    of "acos": r = arccos(x)
    of "atan": r = arctan(x)
    of "exp": r = exp(x)
    of "ln": r = ln(x)
    of "log10": r = log10(x)
    else: discard
    return Quantity(val: r, dim: Dimless)
  # ── engineering formulas (multi-argument) - edit / add your own ──
  of "hypot":
    if args.len != 2: fail("hypot expects 2 arguments"); return
    if not eqDim(args[0].dim, args[1].dim): fail("hypot needs matching units"); return
    return Quantity(val: hypot(args[0].val, args[1].val), dim: args[0].dim)
  of "stress":                 # force / area
    if args.len != 2: fail("stress(force, area) expects 2 arguments"); return
    return qdiv(args[0], args[1])
  of "kinetic":                # 1/2 m v^2
    if args.len != 2: fail("kinetic(mass, velocity) expects 2 arguments"); return
    return qmul(Quantity(val: 0.5, dim: Dimless), qmul(args[0], qpow(args[1], 2)))
  of "hoop":                   # thin-wall hoop stress: p r / t
    if args.len != 3: fail("hoop(pressure, radius, thickness) expects 3 arguments"); return
    return qdiv(qmul(args[0], args[1]), args[2])
  else:
    fail("unknown function: " & name)
    return

# ── tokenizer ───────────────────────────────────────────────────────────────
type
  TokKind = enum tkNum, tkIdent, tkKw, tkOp, tkEnd
  Token = object
    kind: TokKind
    num: float
    text: string

proc tokenize(s: string): seq[Token] =
  var i = 0
  let n = s.len
  while i < n:
    let c = s[i]
    if c in {' ', '\t', '\r', '\n'}:
      inc i
      continue
    if c in {'0' .. '9'} or (c == '.' and i + 1 < n and s[i+1] in {'0' .. '9'}):
      var j = i
      while j < n and s[j] in {'0' .. '9', '.'}: inc j
      if j < n and (s[j] == 'e' or s[j] == 'E'):
        var k = j + 1
        if k < n and (s[k] == '+' or s[k] == '-'): inc k
        if k < n and s[k] in {'0' .. '9'}:
          j = k
          while j < n and s[j] in {'0' .. '9'}: inc j
      let numStr = s[i ..< j]
      var f = 0.0
      if parseFloat(numStr, f) == 0:
        fail("bad number: " & numStr)
        return
      result.add Token(kind: tkNum, num: f)
      i = j
      continue
    if c in {'a' .. 'z', 'A' .. 'Z', '_'}:
      var j = i
      while j < n and s[j] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}: inc j
      let id = s[i ..< j]
      if id == "to" or id == "as":
        result.add Token(kind: tkKw, text: id)
      else:
        result.add Token(kind: tkIdent, text: id)
      i = j
      continue
    if c in {'+', '-', '*', '/', '^', '(', ')', ','}:
      result.add Token(kind: tkOp, text: $c)
      inc i
      continue
    fail("unexpected character: " & $c)
    return
  result.add Token(kind: tkEnd)

# ── recursive-descent parser / evaluator ────────────────────────────────────
type Parser = object
  toks: seq[Token]
  pos: int

proc cur(p: var Parser): Token = p.toks[p.pos]
proc advance(p: var Parser) = inc p.pos

proc parseExpr(p: var Parser): Quantity   # forward declaration

proc parsePrimary(p: var Parser): Quantity =
  let t = cur(p)
  case t.kind
  of tkNum:
    advance(p)
    return Quantity(val: t.num, dim: Dimless)
  of tkOp:
    if t.text == "(":
      advance(p)
      let inner = parseExpr(p)
      if gErr.len > 0: return
      if cur(p).kind == tkOp and cur(p).text == ")":
        advance(p)
      else:
        fail("missing )")
      return inner
    else:
      fail("unexpected '" & t.text & "'")
      return
  of tkIdent:
    let name = t.text
    advance(p)
    if cur(p).kind == tkOp and cur(p).text == "(":     # function call
      advance(p)
      var args: seq[Quantity] = @[]
      if not (cur(p).kind == tkOp and cur(p).text == ")"):
        while true:
          let a = parseExpr(p)
          if gErr.len > 0: return
          args.add a
          if cur(p).kind == tkOp and cur(p).text == ",":
            advance(p)
            continue
          break
      if cur(p).kind == tkOp and cur(p).text == ")":
        advance(p)
      else:
        fail("missing ) in call to " & name)
        return
      return qfunc(name, args)
    var ud: UnitDef
    var cq: Quantity
    if findUnit(name, ud):
      return Quantity(val: ud.factor, dim: ud.dim)
    elif findConst(name, cq):
      return cq
    else:
      fail("unknown name: " & name)
      return
  else:
    fail("unexpected end of input")
    return

proc parsePostfix(p: var Parser): Quantity =
  # implicit multiply by a trailing unit, so "3 kN" and "9.81 m" work.
  var q = parsePrimary(p)
  if gErr.len > 0: return
  while cur(p).kind == tkIdent:
    let nm = cur(p).text
    var ud: UnitDef
    if not findUnit(nm, ud): break
    if p.toks[p.pos + 1].kind == tkOp and p.toks[p.pos + 1].text == "(":
      break   # it is actually a function call; leave it
    advance(p)
    q = qmul(q, Quantity(val: ud.factor, dim: ud.dim))
    if gErr.len > 0: return
  return q

proc parsePower(p: var Parser): Quantity =
  var base = parsePostfix(p)
  if gErr.len > 0: return
  if cur(p).kind == tkOp and cur(p).text == "^":
    advance(p)
    var neg = false
    if cur(p).kind == tkOp and (cur(p).text == "-" or cur(p).text == "+"):
      neg = cur(p).text == "-"
      advance(p)
    if cur(p).kind != tkNum:
      fail("exponent must be an integer")
      return
    let e = cur(p).num
    advance(p)
    if e != floor(e):
      fail("exponent must be an integer")
      return
    var ei = int(e)
    if neg: ei = -ei
    base = qpow(base, ei)
  return base

proc parseUnary(p: var Parser): Quantity =
  if cur(p).kind == tkOp and (cur(p).text == "-" or cur(p).text == "+"):
    let neg = cur(p).text == "-"
    advance(p)
    var q = parseUnary(p)
    if gErr.len > 0: return
    if neg: q.val = -q.val
    return q
  return parsePower(p)

proc parseMul(p: var Parser): Quantity =
  var a = parseUnary(p)
  if gErr.len > 0: return
  while cur(p).kind == tkOp and (cur(p).text == "*" or cur(p).text == "/"):
    let op = cur(p).text
    advance(p)
    let b = parseUnary(p)
    if gErr.len > 0: return
    if op == "*": a = qmul(a, b)
    else: a = qdiv(a, b)
    if gErr.len > 0: return
  return a

proc parseAdd(p: var Parser): Quantity =
  var a = parseMul(p)
  if gErr.len > 0: return
  while cur(p).kind == tkOp and (cur(p).text == "+" or cur(p).text == "-"):
    let op = cur(p).text
    advance(p)
    let b = parseMul(p)
    if gErr.len > 0: return
    if op == "+": a = qadd(a, b)
    else: a = qsub(a, b)
    if gErr.len > 0: return
  return a

proc parseExpr(p: var Parser): Quantity =
  parseAdd(p)

# ── formatting ──────────────────────────────────────────────────────────────
proc niceNum(x: float): string =
  if x == 0.0: return "0"
  # 12 significant digits absorbs the floating-point noise that full
  # round-trip printing would expose; then trim the padded trailing zeros.
  result = formatFloat(x, ffDefault, 12)
  if ('e' notin result) and ('E' notin result) and ('.' in result):
    var last = result.len - 1
    while last > 0 and result[last] == '0': dec last
    if result[last] == '.': dec last
    result.setLen(last + 1)

proc dimString(dm: Dim): string =
  const bases = ["m", "kg", "s", "A", "K", "mol", "cd"]
  var parts: seq[string] = @[]
  for i in 0 .. 6:
    if dm[i] != 0:
      if dm[i] == 1: parts.add bases[i]
      else: parts.add bases[i] & "^" & $dm[i]
  result = parts.join("*")

proc preferredName(dm: Dim): string =
  for it in preferred:
    if eqDim(it.dm, dm): return it.name
  return ""

proc formatQ(q: Quantity): string =
  if isDimless(q.dim): return niceNum(q.val)
  let pn = preferredName(q.dim)
  if pn.len > 0: return niceNum(q.val) & " " & pn
  return niceNum(q.val) & " " & dimString(q.dim)

proc evalToString(input: string): string =
  gErr = ""
  let trimmed = input.strip()
  if trimmed.len == 0: return ""
  let toks = tokenize(trimmed)
  if gErr.len > 0: return "Error: " & gErr
  var p = Parser(toks: toks, pos: 0)
  let q = parseExpr(p)
  if gErr.len > 0: return "Error: " & gErr
  if cur(p).kind == tkKw:                 # optional "to"/"as" <unit> conversion
    advance(p)
    if cur(p).kind != tkIdent:
      return "Error: expected a unit after 'to'"
    let uname = cur(p).text
    advance(p)
    var ud: UnitDef
    if not findUnit(uname, ud):
      return "Error: unknown unit: " & uname
    if not eqDim(ud.dim, q.dim):
      return "Error: cannot convert " & dimString(q.dim) & " to " & uname
    if cur(p).kind != tkEnd:
      return "Error: unexpected input after conversion"
    return niceNum(q.val / ud.factor) & " " & uname
  if cur(p).kind != tkEnd:
    return "Error: unexpected token near end of input"
  return formatQ(q)

# ── exports: the only surface the JS shell touches ──────────────────────────
var ioBuf: array[1 shl 16, char]        # 64 KB shared I/O buffer

proc bufAddr(): pointer {.exportc, used,
    codegenDecl: "__attribute__((export_name(\"bufAddr\"), used)) $# $#$#".} =
  cast[pointer](addr ioBuf[0])

proc evalBuf(n: cint): cint {.exportc, used,
    codegenDecl: "__attribute__((export_name(\"evalBuf\"), used)) $# $#$#".} =
  let m = n.int
  var s = newString(m)
  if m > 0:
    copyMem(addr s[0], addr ioBuf[0], m)
  let res = evalToString(s)
  var outLen = res.len
  if outLen > ioBuf.len: outLen = ioBuf.len
  if outLen > 0:
    copyMem(addr ioBuf[0], unsafeAddr res[0], outLen)
  result = outLen.cint
