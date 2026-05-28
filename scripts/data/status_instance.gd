class_name StatusInstance
extends RefCounted

var status_id: String = ""
var value: int = 0
var stacks: int = 1
var duration: int = 0
var source_uid: String = ""
var payload: Dictionary = {}


static func create(
	status_id: String,
	stacks: int = 1,
	duration: int = 0,
	source_uid: String = "",
	payload: Dictionary = {}
) -> StatusInstance:
	var status := StatusInstance.new()
	status.status_id = status_id
	status.stacks = stacks
	status.duration = duration
	status.source_uid = source_uid
	status.payload = payload.duplicate()
	return status


func clone() -> StatusInstance:
	var status := StatusInstance.new()
	status.status_id = status_id
	status.value = value
	status.stacks = stacks
	status.duration = duration
	status.source_uid = source_uid
	status.payload = payload.duplicate(true)
	return status
