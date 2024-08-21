import std/setutils, strutils

type context* = object
  source_id: int
  start: int
  finish: int

const STRING_FIRST = setutils.toSet("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
const STRING_NEXT  = setutils.toSet("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
const NUMBER_FIRST = setutils.toSet("0123456789-+")
const NUMBER_NEXT  = setutils.toSet("0123456789")

var buffers = @[""]

proc new_context*(source: string): context =
  buffers.add(source & '\0')
  return context(
    source_id: buffers.high,
    start: 0,
    finish: source.high,
  )

proc source*(context: context): string =
  return buffers[context.source_id]

proc inc*(context: var context, amount = 1) =
  context.start += amount

proc get_index*(context: context): int =
  return context.start

proc set_index*(context: var context, value: int) =
  context.start = value

proc dbg*(c: context): string =
  return "\u001b[31m" & source(c)[0..c.start - 1] & "\u001b[0m" & source(c)[c.start..^1]

proc peek*(c: context): char =
  return c.source[c.start]

proc peek*(c: context, offset: int): char =
  return c.source[c.start + offset]

proc read*(c: var context): char =
  result = c.source[c.start]
  if result != '\0':
    c.start += 1

proc skip_comment*(c: var context): bool =
  if peek(c) == ';' or (peek(c) == '/' and peek(c, 1) == '/'):
    while peek(c) notin {'\n', '\0'}:
      c.start += 1
    return true
  if peek(c) == '/' and peek(c, 1) == '*':
    while peek(c) != '\0' and (peek(c) != '*' or peek(c, 1) != '/'):
      c.start += 1
    return true

proc skip_whitespaces*(c: var context) =
  while peek(c) in {' ', '\t', '\r'}:
    c.start += 1
  if skip_comment(c):
    skip_whitespaces(c)

proc skip_newlines*(c: var context) =
  while peek(c) in {' ', '\r', '\n', '\t'}:
    c.start += 1
  if skip_comment(c):
    skip_newlines(c)

proc matches*(c: var context, value: string, increment = true): bool =
  for i in 0..value.high:
    if peek(c, i) != value[i]: 
      return false
  if increment:
    c.start += value.len
  return true

proc matches*(c: var context, value: char): bool =
  if peek(c) == value:
    c.start += 1
    return true

proc get_string*(c: var context): context =
  result = c
  result.finish = c.start

  if peek(c) notin STRING_FIRST: 
    return

  inc(c)
  result.finish += 1

  while peek(c) in STRING_NEXT:
    inc(c)
    result.finish += 1

proc get_unsigned*(c: var context): string =
  if peek(c) == '0':
    var value = 0'u64
    if peek(c, 1) == 'x':
      c.start += 2
      result = "0x"
      while peek(c) in setutils.toSet("0123456789abcdefABCDEF"):
        result.add(read(c))
      return result
    if peek(c, 1) == 'o':
      c.start += 2
      result = "0o"
      while peek(c) in setutils.toSet("01234567"):
        result.add(read(c))
      return result
    if peek(c, 1) == 'b':
      c.start += 2
      result = "0b"
      while peek(c) in setutils.toSet("01"):
        result.add(read(c))
      return result

  if peek(c) notin NUMBER_FIRST:
    return
  result.add(read(c))
  while peek(c) in NUMBER_NEXT:
    result.add(read(c))

func parse_unsigned*(input: string): uint64 =
  if input.len < 3: 
    try:
      return cast[uint64](parseInt(input))
    except: return 0
  case input[1]:
    of 'x': return fromHex[uint64](input)
    of 'o': return fromOct[uint64](input)
    of 'b': return fromBin[uint64](input)
    else:   return cast[uint64](parseInt(input))

proc get_signed*(c: var context): string =
  
  if c.peek() == '-':
    result.add('-')
    c.start += 1

  result.add(c.get_unsigned())

proc parse_signed*(input: string): int =
  if input.len == 0: return

  if input[0] == '-':
    return -1 * cast[int](parse_unsigned(input[1..^1]))
  return cast[int](parse_unsigned(input))

proc get_line_number*(c: context): int =
  var line = 1
  for i in 0..c.start - 1:
    if c.source[i] == '\n':
      line += 1
  return line

proc get_size*(c: var context): int =
  if peek(c) != '<' or peek(c, 1) != 'U': return
  let orig_index = c.start
  c.start += 2
  let number = get_unsigned(c)
  if number == "" or read(c) != '>':
    c.start = orig_index
    return

  return parseInt(number)

proc length*(c: context): int =
  return c.finish - c.start

proc `$`*(c: context): string =
  return source(c)[c.start..c.finish - 1]

iterator items(c: context): char =
  var i = c.start
  while i < c.finish:
    yield source(c)[i]
    i += 1

iterator pairs(c: context): (int, char) =
  var i = c.start
  while i < c.finish:
    yield (i - c.start, source(c)[i])
    i += 1

proc `[]`(c: context, index: int): char =
  return source(c)[index]

proc `==`*(a: context, b: context): bool =
  if a == b: return true
  if a.length != b.length: return false
  for i, c in a:
    if b[i] != c: return false
  return true

proc `==`*(a: context, b: string): bool =
  if a.length != b.len: return false
  for i, c in a:
    if b[i] != c: return false
  return true

proc `==`*(a: string, b: context): bool =
  return b == a

proc to_context*(input: string): context =
  result = context(start: buffers[0].len)
  buffers[0] &= input
  result.finish = buffers[0].high

proc `&`*(a: context, b: context): context =
  return to_context($a & $b)

proc `&`*(a: context, b: string): context =
  return to_context($a & $b)

proc `&`*(a: string, b: context): context =
  return to_context($a & $b)
