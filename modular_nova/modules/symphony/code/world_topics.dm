/datum/world_topic/whitelist_revoke
	keyword = "whitelist_revoke"
	require_comms_key = TRUE

/datum/world_topic/whitelist_revoke/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	if(!target_ckey)
		.["success"] = FALSE
		.["message"] = "missing target_ckey"
		return
	symphony_revoke(target_ckey)
	.["success"] = TRUE

/datum/world_topic/whitelist_grant
	keyword = "whitelist_grant"
	require_comms_key = TRUE

/datum/world_topic/whitelist_grant/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	if(!target_ckey)
		.["success"] = FALSE
		.["message"] = "missing target_ckey"
		return
	symphony_notify_grant(target_ckey)
	.["success"] = TRUE
