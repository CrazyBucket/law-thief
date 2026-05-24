class_name StatusInstance
extends RefCounted

var status_id: String = ""
var value: int = 0
var stacks: int = 1
var duration: int = 0
var source_uid: String = ""


static func create(status_id: String, stacks: int = 1, duration: int = 0, source_uid: String = "") -> StatusInstance:
	var status := StatusInstance.new()
	status.status_id = status_id
	status.stacks = stacks
	status.duration = duration
	status.source_uid = source_uid
	return status
