/// The in-game roles SSymphony can map Discord roles to. This list is the source of truth - the panel cannot add any.
/// Key = what the game checks with symphony_has_ingame_role(), value = the description shown in the panel.
GLOBAL_LIST_INIT(symphony_ingame_roles, list(
	"whitelist" = "Required to join the round.",
))

/// Hands the defined roles over so SSymphony can populate its role-mapping UI.
/datum/world_topic/symphony/ingame_roles
	keyword = "symphony_ingame_roles"
	require_comms_key = TRUE

/datum/world_topic/symphony/ingame_roles/Run(list/input)
	. = list()
	var/list/roles = list()
	for(var/key in GLOB.symphony_ingame_roles)
		roles += list(list("key" = key, "description" = GLOB.symphony_ingame_roles[key]))
	.["roles"] = roles
