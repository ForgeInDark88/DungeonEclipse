class_name EquipSlotDef
extends Resource
## One equipment slot. The list lives in data/equipment_layout.tres; add an
## entry there to get a new slot (logic and UI pick it up automatically).

@export var id: StringName
## Which EquipmentItemData.slot_type fits here.
@export var slot_type: StringName
@export var label: String = ""
## Faded icon drawn in the empty slot.
@export var placeholder: Texture2D
## Position on the left page of the inventory book (relative to the doll area).
@export var page_position: Vector2 = Vector2.ZERO
