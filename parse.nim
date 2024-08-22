import std/setutils, strutils, hashes, tables

type stream_slice* = object
  source: ref string
  source_id: int
  start: int
  finish: int

const STRING_FIRST = setutils.toSet("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
const STRING_NEXT  = setutils.toSet("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
const NUMBER_FIRST = setutils.toSet("0123456789-+")
const NUMBER_NEXT  = setutils.toSet("0123456789")

var buffers = @[""]

proc new_stream_slice*(source: string): stream_slice =
  buffers.add(source & '\0')
  var reference = new(string)
  reference[] = source & '\0'
  return stream_slice(
    source: reference,
    source_id: buffers.high,
    start: 0,
    finish: source.len,
  )

func finished*(s: stream_slice): bool =
  assert not isNil(s.source)
  return s.start >= s.finish

func len*(s: stream_slice): int =
  assert not isNil(s.source)
  return s.finish - s.start

func `$`*(s: stream_slice): string =
  assert not isNil(s.source)
  return s.source[s.start..s.finish - 1]

func `[]`(s: stream_slice, index: int): char =
  assert not isNil(s.source)
  return s.source[s.start + index]

func `[]`(s: stream_slice, index: HSlice): stream_slice =
  assert not isNil(s.source)
  result = s
  result.start  += index.a
  result.finish -= index.b.int

func skip*(s: var stream_slice, amount = 1) =
  assert not isNil(s.source)
  s.start += amount

func get_index*(s: stream_slice): int =
  assert not isNil(s.source)
  return s.start

func set_index*(s: var stream_slice, value: int) =
  assert not isNil(s.source)
  s.start = value

func dbg*(s: stream_slice): string =
  return "\u001b[31m" & s.source[0..s.start - 1] & "\u001b[0m" & s.source[s.start..^1]

func peek*(s: stream_slice): char =
  assert not isNil(s.source)
  return s.source[s.start]

func peek*(s: stream_slice, offset: int): char =
  assert not isNil(s.source)
  return s.source[s.start + offset]

func read*(s: var stream_slice): char =
  assert not isNil(s.source)
  result = s.source[s.start]
  if result != '\0':
    s.start += 1

func skip_comment*(s: var stream_slice): bool =
  if peek(s) == ';' or (peek(s) == '/' and peek(s, 1) == '/'):
    while peek(s) notin {'\n', '\0'}:
      s.start += 1
    return true
  if peek(s) == '/' and peek(s, 1) == '*':
    while peek(s) != '\0' and (peek(s) != '*' or peek(s, 1) != '/'):
      s.start += 1
    return true

proc skip_whitespaces*(s: var stream_slice) =
  while peek(s) in {' ', '\t', '\r'}:
    s.start += 1
  if skip_comment(s):
    skip_whitespaces(s)

proc skip_newlines*(s: var stream_slice) =
  while peek(s) in {' ', '\r', '\n', '\t'}:
    s.start += 1
  if skip_comment(s):
    skip_newlines(s)

proc matches*(s: var stream_slice, value: string, increment = true): bool =
  for i in 0..value.high:
    if peek(s, i) != value[i]: 
      return false
  if increment:
    s.start += value.len
  return true

proc matches*(s: var stream_slice, value: char): bool =
  if peek(s) == value:
    s.start += 1
    return true

proc get_string*(s: var stream_slice): stream_slice =
  result = s
  result.finish = s.start

  if peek(s) notin STRING_FIRST: 
    return

  skip(s)
  result.finish += 1

  while peek(s) in STRING_NEXT:
    skip(s)
    result.finish += 1

proc get_unsigned*(s: var stream_slice): stream_slice =
  result = s
  result.finish = s.start
  if peek(s) == '0':
    var value = 0'u64
    if peek(s, 1) == 'x':
      skip(s, 2)
      result.finish += 2
      while peek(s) in setutils.toSet("0123456789abcdefABCDEF"):
        skip(s)
        result.finish += 1
      return result
    if peek(s, 1) == 'o':
      skip(s, 2)
      result.finish += 2
      while peek(s) in setutils.toSet("01234567"):
        skip(s)
        result.finish += 1
      return result
    if peek(s, 1) == 'b':
      skip(s, 2)
      result.finish += 2
      while peek(s) in setutils.toSet("01"):
        skip(s)
        result.finish += 1
      return result

  if peek(s) notin NUMBER_FIRST:
    return
  skip(s)
  result.finish += 1
  while peek(s) in NUMBER_NEXT:
    skip(s)
    result.finish += 1

func parse_unsigned*(s: stream_slice): uint64 =
  if s.len < 3: 
    try:
      return cast[uint64](parseInt($s))
    except: return 0

  case s[1]:
    of 'x': return fromHex[uint64]($s)
    of 'o': return fromOct[uint64]($s)
    of 'b': return fromBin[uint64]($s)
    else:   return cast[uint64](parseInt($s))

proc get_signed*(s: var stream_slice): stream_slice =
  
  let negative = s.peek() == '-'
  if negative:
    skip(s)

  result = s.get_unsigned()
  if negative:
    result.start -= 1

proc parse_signed*(s: stream_slice): int =
  if s.len == 0: return

  if s[0] == '-':
    return -1 * cast[int](parse_unsigned(s[1..^1]))
  return cast[int](parse_unsigned(s))

proc get_line_number*(s: stream_slice): int =
  var line = 1
  for i in 0..s.start - 1:
    if s.source[i] == '\n':
      line += 1
  return line

func get_size*(s: var stream_slice): int =
  if peek(s) != '<' or peek(s, 1) != 'U': return
  let orig_index = s.start
  s.start += 2
  let number = $get_unsigned(s)
  if number == "" or read(s) != '>':
    s.start = orig_index
    return

  return parseInt(number)

iterator items(s: stream_slice): char =
  var i = s.start
  while i < s.finish:
    yield s.source[i]
    i += 1

iterator pairs(s: stream_slice): (int, char) =
  var i = s.start
  while i < s.finish:
    yield (i - s.start, s.source[i])
    i += 1

func `==`*(a: stream_slice, b: stream_slice): bool =
  if a.source_id == b.source_id and a.start == b.start and a.finish == b.finish: return true
  if a.len != b.len: return false
  for i, c in a:
    if b[i] != c: return false
  return true

func `==`*(a: stream_slice, b: string): bool =
  if a.len != b.len: return false
  for i, c in a:
    if b[i] != c: return false
  return true

func `==`*(a: string, b: stream_slice): bool =
  return b == a

proc `&`*(a: stream_slice, b: stream_slice): stream_slice =
  return new_stream_slice($a & $b)

proc `&`*(a: stream_slice, b: string): stream_slice =
  return new_stream_slice($a & $b)

proc `&`*(a: string, b: stream_slice): stream_slice =
  return new_stream_slice($a & $b)

proc hash*(s: stream_slice): Hash =
  # Needed for contexts to be keys in maps
  var h: Hash = 0
  for c in s:
    h = h !& hash(c)
  result = !$h  

proc get_quoted_string*(s: var stream_slice): stream_slice =
  
  let restore = s

  let quote = s.read()

  if quote notin {'"', '\'', '`'}: 
    s = restore
    return

  var next = read(s)

  while next != quote or peek(s, -1) == '\\':
    next = read(s)
    if finished(s):
      s = restore
      return

  result = s
  result.start  = restore.start + 1
  result.finish = s.start - 1

proc get_encapsulation*(s: var stream_slice): stream_slice =

  let restore = s

  let open = read(s)
  var close: char

  case open:
    of '(': close = ')'
    of '[': close = ']'
    of '{': close = '}'
    else:
      s = restore
      return

  var depth = 1
  while depth > 0:
    let c = read(s)
    if c == open: depth += 1
    if c == close: depth -= 1

    if c in {'"', '\'', '`'}:
      s.start -= 1
      discard get_quoted_string(s)

    if finished(s): 
      s = restore
      return

  result = s
  result.start  = restore.start + 1
  result.finish = s.start - 1

