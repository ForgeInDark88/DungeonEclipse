class_name NetInterp
extends RefCounted
## Smooth movement of a remote copy (a teammate's hero on my screen, a
## monster shell on a guest): snapshot interpolation.
##
## Snapshots carry the SENDER's clock. They are kept in a short buffer and
## the copy is drawn DELAY seconds in the past, between the two snapshots
## around that moment - so packets that arrive in bursts, late or out of
## order no longer make it jump forward and snap back (the old "lerp to the
## latest + guess a speed from arrival times" did exactly that). Older
## packets than the newest are dropped; a lost one is just interpolated
## over; only when the stream stops does it extrapolate a little.

const DELAY := 0.1  # seconds behind the newest snapshot
const MAX_EXTRAPOLATE := 0.2
const TELEPORT := 160.0  # a hop this long is a teleport: no gliding through walls

var _t: PackedFloat64Array = []
var _p: PackedVector2Array = []
var _render_t := -1.0


## Forget the history and stand here (floor change, respawn, spawn).
func reset(pos: Vector2) -> void:
	_t.clear()
	_p.clear()
	_render_t = -1.0
	_last = pos


var _last := Vector2.ZERO


func push(sender_time: float, pos: Vector2) -> void:
	var n := _t.size()
	if n > 0 and sender_time <= _t[n - 1]:
		return  # late or duplicate packet: the newer one already arrived
	if n > 0 and pos.distance_to(_p[n - 1]) > TELEPORT:
		_t.clear()  # teleport: start a fresh history there
		_p.clear()
		_render_t = -1.0
	_t.append(sender_time)
	_p.append(pos)
	if _t.size() > 24:
		_t = _t.slice(_t.size() - 24)
		_p = _p.slice(_p.size() - 24)


func has_data() -> bool:
	return not _t.is_empty()


## Where the copy should be this frame.
func sample(delta: float) -> Vector2:
	var n := _t.size()
	if n == 0:
		return _last
	var newest := _t[n - 1]
	var want := newest - DELAY
	if _render_t < 0.0 or absf(_render_t - want) > 0.35:
		_render_t = want  # first data or far out of step: jump to the right moment
	else:
		# advance with real time, nudged toward the target delay (clock drift,
		# bursts) so it never runs away from the stream
		_render_t += delta + (want - _render_t) * minf(1.0, delta * 3.0)
	if n == 1 or _render_t <= _t[0]:
		_last = _p[0] if _render_t <= _t[0] else _p[n - 1]
		return _last
	if _render_t >= newest:
		# the stream is late: keep going along the last hop a little
		var dt := maxf(0.001, newest - _t[n - 2])
		var vel := (_p[n - 1] - _p[n - 2]) / dt
		_last = _p[n - 1] + vel * minf(_render_t - newest, MAX_EXTRAPOLATE)
		return _last
	var i := n - 2
	while i > 0 and _t[i] > _render_t:
		i -= 1
	var span := maxf(0.0001, _t[i + 1] - _t[i])
	_last = _p[i].lerp(_p[i + 1], clampf((_render_t - _t[i]) / span, 0.0, 1.0))
	return _last


## Seconds on this machine's clock (what senders stamp their snapshots with).
static func now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
