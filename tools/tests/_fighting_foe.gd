extends Node2D
## A stand-in monster for audio_test: "fights" until told otherwise.
var fighting := true


func is_fighting() -> bool:
	return fighting
