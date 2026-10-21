class_name HeroAnimator
extends Node
## Finite state machine choosing the hero animation.
## Priority: DEATH > HURT > ACTION (attack / use / interact, one-shot)
## > DASH > CLIMB > JUMP/FALL > LAND (one-shot) > RUN/IDLE.

enum State { IDLE, RUN, JUMP, FALL, LAND, CLIMB, DASH, ACTION, HURT, DEATH }

const HURT_TIME := 0.25
const RUN_THRESHOLD := 12.0

var state: State = State.IDLE
var visual: HeroVisual
var _action: StringName = &""
var _hurt_left := 0.0


func setup(p_visual: HeroVisual) -> void:
	visual = p_visual
	visual.animation_finished.connect(_on_animation_finished)
	visual.play(&"idle")


## Called every physics frame by the Player.
func update(delta: float, on_floor: bool, velocity: Vector2, climbing: bool, dashing: bool) -> void:
	match state:
		State.DEATH:
			return
		State.HURT:
			_hurt_left -= delta
			if _hurt_left > 0.0:
				return
		State.ACTION:
			return
		State.LAND:
			# Moving cancels the landing pose for responsiveness.
			if absf(velocity.x) < RUN_THRESHOLD * 4.0 and on_floor:
				return
	_locomotion(on_floor, velocity, climbing, dashing)


func _locomotion(on_floor: bool, velocity: Vector2, climbing: bool, dashing: bool) -> void:
	visual.hand_visible = true
	if dashing:
		_enter(State.DASH, &"dash")
	elif climbing:
		_enter(State.CLIMB, &"climb")
		visual.hand_visible = false
		visual.set_paused(velocity.length() < 1.0)
		return
	elif not on_floor:
		_enter(State.JUMP if velocity.y < 0.0 else State.FALL, &"jump" if velocity.y < 0.0 else &"fall")
	elif absf(velocity.x) > RUN_THRESHOLD:
		_enter(State.RUN, &"run")
	else:
		_enter(State.IDLE, &"idle")
	visual.set_paused(false)


func _enter(new_state: State, anim: StringName) -> void:
	state = new_state
	visual.play(anim)


func landed() -> void:
	if state in [State.DEATH, State.ACTION, State.HURT]:
		return
	state = State.LAND
	visual.set_paused(false)
	visual.play(&"land", 1.0, true)


## One-shot animation (attack_*, use, interact). `duration` > 0 speeds the
## animation up so it fits (e.g. into the attack cooldown).
func play_action(anim: StringName, duration := 0.0) -> void:
	if state == State.DEATH or not visual.layout.has_animation(anim):
		return
	var speed := 1.0
	var length := visual.layout.duration(anim)
	if duration > 0.0 and length > duration:
		speed = length / duration
	state = State.ACTION
	_action = anim
	visual.hand_visible = true
	visual.set_paused(false)
	visual.play(anim, speed, true)


func hurt() -> void:
	if state == State.DEATH:
		return
	state = State.HURT
	_hurt_left = HURT_TIME
	visual.set_paused(false)
	visual.play(&"hurt", 1.0, true)


func die() -> void:
	state = State.DEATH
	visual.set_paused(false)
	visual.play(&"death", 1.0, true)


func is_busy() -> bool:
	return state == State.ACTION


func _on_animation_finished(anim: StringName) -> void:
	if state == State.ACTION and anim == _action:
		state = State.IDLE
	elif state == State.LAND and anim == &"land":
		state = State.IDLE
