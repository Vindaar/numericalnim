import strformat, math
import utils
import ./common/commonTypes

type
  SplineType*[T] = CubicSpline[T] or HermiteSpline[T]
  CubicSpline*[T] = ref object
    X: seq[float]
    high: int
    len: int
    coeffs: seq[array[5, T]]
  HermiteSpline*[T] = ref object
    # Lazy evaluation
    X: seq[float]
    high: int
    len: int
    Y: seq[T]
    dY: seq[T]
  SplineProc*[T] = proc(x: float): T

proc findInterval*(list: openArray[float], x: float): int {.inline.} =
  ## Finds the index of the element to the left of x in list using binary search. list must be ordered.
  let highIndex = list.high
  if x < list[0] or list[highIndex] < x:
    raise newException(ValueError, &"x = {x} isn't in the interval [{list[0]}, {list[highIndex]}]")
  var upper = highIndex
  var lower = 0
  var n = floorDiv(upper + lower, 2)
  # find interval using binary search
  for i in 0 .. highIndex:
    if x < list[n]:
      # x is below current interval
      upper = n
      n = floorDiv(upper + lower, 2)
      continue
    if list[n+1] < x:
      # x is above current interval
      lower = n + 1
      n = floorDiv(upper + lower, 2)
      continue
    # x is in the interval
    return n

### CubicSpline

proc constructCubicSpline[T](X: openArray[float], Y: openArray[T]): seq[array[5, float]] =
  let n = X.len - 1
  var a = newSeq[T](n+1)
  var b = newSeq[float](n)
  var d = newSeq[float](n)
  var h = newSeq[float](n)
  for i in 0 ..< n:
    a[i] = Y[i]
    h[i] = X[i+1] - X[i]
  a[n] = Y[n]
  var alpha = newSeq[T](n)
  for i in 1 ..< n:
    alpha[i] = 3.0 / h[i] * (a[i+1] - a[i]) - 3.0 / h[i-1] * (a[i] - a[i-1])
  var c = newSeq[T](n+1)
  var mu = newSeq[float](n+1)
  var l = newSeq[float](n+1)
  var z = newSeq[T](n+1)
  l[0] = 1.0
  mu[0] = 0.0
  z[0] = 0.0
  for i in 1 ..< n:
    l[i] = 2.0 * (X[i+1] - X[i-1]) - h[i-1]*mu[i-1]
    mu[i] = h[i] / l[i]
    z[i] = (alpha[i] - h[i-1]*z[i-1]) / l[i]
  l[n] = 1.0
  z[n] = 0.0
  c[n] = 0.0
  for j in countdown(n-1, 0):
    c[j] = z[j] - mu[j]*c[j+1]
    b[j] = (a[j+1]-a[j])/h[j] - h[j] * (c[j+1] + 2.0*c[j]) / 3.0
    d[j] = (c[j+1] - c[j]) / (3.0 * h[j])
  result = newSeq[array[5, float]](n)
  for i in 0 ..< n:
    result[i] = [a[i], b[i], c[i], d[i], X[i]]


proc newCubicSpline*[T: SomeFloat](X: openArray[float], Y: openArray[T]): CubicSpline[T] =
  let sortedData = sortDataset(X, Y)
  var xSorted = newSeq[float](X.len)
  var ySorted = newSeq[T](Y.len)
  for i in 0 .. sortedData.high:
    xSorted[i] = sortedData[i][0]
    ySorted[i] = sortedData[i][1]
  let coeffs = constructCubicSpline(xSorted, ySorted)
  result = CubicSpline[T](X: xSorted, coeffs: coeffs, high: xSorted.high, len: xSorted.len)

proc eval*[T](spline: CubicSpline[T], x: float): T =
  let n = findInterval(spline.X, x)
  let a = spline.coeffs[n][0]
  let b = spline.coeffs[n][1]
  let c = spline.coeffs[n][2]
  let d = spline.coeffs[n][3]
  let xj = spline.coeffs[n][4]
  let xDiff = x - xj
  return a + b * xDiff + c * xDiff * xDiff + d * xDiff * xDiff * xDiff

proc derivEval*[T](spline: CubicSpline[T], x: float): T =
  let n = findInterval(spline.X, x)
  let b = spline.coeffs[n][1]
  let c = spline.coeffs[n][2]
  let d = spline.coeffs[n][3]
  let xj = spline.coeffs[n][4]
  let xDiff = x - xj
  return b + 2 * c * xDiff + 3 * d * xDiff * xDiff

## HermiteSpline

proc newHermiteSpline*[T](X: openArray[float], Y, dY: openArray[T]): HermiteSpline[T] =
  let sortedData = sortDataset(X, Y)
  let sortedData_dY = sortDataset(X, dY)
  var xSorted = newSeq[float](X.len)
  var ySorted = newSeq[T](Y.len)
  var dySorted = newSeq[T](dY.len)
  for i in 0 .. sortedData.high:
    xSorted[i] = sortedData[i][0]
    ySorted[i] = sortedData[i][1]
    dySorted[i] = sortedData_dY[i][1]
  result = HermiteSpline[T](X: xSorted, Y: ySorted, dY: dySorted, high: xSorted.high, len: xSorted.len)

proc newHermiteSpline*[T](X: openArray[float], Y: openArray[T]): HermiteSpline[T] =
  # if only (x, y) is given, use three-point differenceto calculate dY.
  let sortedData = sortDataset(X, Y)
  var xSorted = newSeq[float](X.len)
  var ySorted = newSeq[T](Y.len)
  var dySorted = newSeq[T](Y.len)
  for i in 0 .. sortedData.high:
    xSorted[i] = sortedData[i][0]
    ySorted[i] = sortedData[i][1]
  let highest = dySorted.high
  dySorted[0] = (ySorted[1] - ySorted[0]) / (xSorted[1] - xSorted[0])
  dySorted[highest] = (ySorted[highest] - ySorted[highest-1]) / (xSorted[highest] - xSorted[highest-1])
  for i in 1 .. highest-1:
    dySorted[i] = 0.5 * ((ySorted[i+1] - ySorted[i])/(xSorted[i+1] - xSorted[i]) + (ySorted[i] - ySorted[i-1])/(xSorted[i] - xSorted[i-1]))
  result = HermiteSpline[T](X: xSorted, Y: ySorted, dY: dySorted, high: xSorted.high, len: xSorted.len)

proc eval*[T](spline: HermiteSpline[T], x: float): T =
  let n = findInterval(spline.X, x)
  let xDiff = spline.X[n+1] - spline.X[n]
  let t = (x - spline.X[n]) / xDiff
  let t2 = t * t
  let t3 = t2 * t
  let h00 = 2*t3 - 3*t2 + 1
  let h10 = t3 - 2*t2 + t
  let h01 = -2*t3 + 3*t2
  let h11 = t3 - t2
  let p1 = spline.Y[n]
  let p2 = spline.Y[n+1]
  let m1 = spline.dY[n]
  let m2 = spline.dY[n+1]
  result = h00*p1 + h10*xDiff*m1 + h01*p2 + h11*xDiff*m2

proc derivEval*[T](spline: HermiteSpline[T], x: float): T =
  let n = findInterval(spline.X, x)
  let xDiff = spline.X[n+1] - spline.X[n]
  let t = (x - spline.X[n]) / xDiff
  let t2 = t * t
  let h00 = 6*t2 - 6*t
  let h10 = 3*t2 - 4*t + 1
  let h01 = -6*t2 + 6*t
  let h11 = 3*t2 - 2*t
  let p1 = spline.Y[n]
  let p2 = spline.Y[n+1]
  let m1 = spline.dY[n]
  let m2 = spline.dY[n+1]
  result = (h00*p1 + h10*xDiff*m1 + h01*p2 + h11*xDiff*m2) / xDiff


# General Spline stuff
proc eval*[T](spline: SplineType[T], x: openArray[float]): seq[T] =
  result = newSeq[T](x.len)
  for i, xi in x:
    result[i] = eval(spline, xi)

proc toProc*[T](spline: SplineType[T]): SplineProc[T] =
  result = proc(x: float): T = eval(spline, x)

proc toOptionalProc*[T](spline: SplineType[T]): NumContextProc[T] =
  result = proc(x: float, ctx: NumContext[T]): T = eval(spline, x)

proc derivEval*[T](spline: SplineType[T], x: openArray[float]): seq[T] =
  result = newSeq[T](x.len)
  for i, xi in x:
    result[i] = derivEval(spline, xi)

proc toDerivProc*[T](spline: SplineType[T]): SplineProc[T] =
  result = proc(x: float): T = derivEval(spline, x)

proc toDerivOptionalProc*[T](spline: SplineType[T]): proc(x: float, ctx: NumContext[T]): T =
  result = proc(x: float, ctx: NumContext[T]): T = derivEval(spline, x)
