@tool
extends RefCounted

const FrameBuilder := preload("res://scripts/edger_builders/edger_frame_builder.gd")
const InfeedBuilder := preload("res://scripts/edger_builders/edger_infeed_builder.gd")
const PinBuilder := preload("res://scripts/edger_builders/edger_pin_builder.gd")
const OutfeedBuilder := preload("res://scripts/edger_builders/edger_outfeed_builder.gd")
const SawBuilder := preload("res://scripts/edger_builders/edger_saw_builder.gd")

var edger: SawmillEdger
var frame_builder: RefCounted
var infeed_builder: RefCounted
var pin_builder: RefCounted
var outfeed_builder: RefCounted
var saw_builder: RefCounted


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger
	frame_builder = FrameBuilder.new(edger)
	pin_builder = PinBuilder.new(edger)
	infeed_builder = InfeedBuilder.new(edger, pin_builder)
	outfeed_builder = OutfeedBuilder.new(edger)
	saw_builder = SawBuilder.new(edger)


func build_frame() -> void:
	frame_builder.build_frame()


func build_feed_deck() -> void:
	frame_builder.build_side_fences()
	infeed_builder.build_infeed_chains()
	outfeed_builder.build_lower_feed_rollers()


func build_infeed_chains() -> void:
	infeed_builder.build_infeed_chains()


func build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	infeed_builder.build_parking_ramps(chain_start, chain_end, chain_top)


func build_infeed_hold_downs(chain_start: float, chain_end: float) -> void:
	infeed_builder.build_infeed_hold_downs(chain_start, chain_end)


func build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	pin_builder.build_position_pins(chain_start, chain_end, chain_top)


func build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	pin_builder.build_cushion_pins(chain_start, chain_end, chain_top)


func build_hold_downs() -> void:
	outfeed_builder.build_hold_downs()


func build_saw_box() -> void:
	saw_builder.build_saw_box()


func build_motors_and_drives() -> void:
	saw_builder.build_motors_and_drives()


func build_waste_handling() -> void:
	outfeed_builder.build_waste_handling()


