/// The in-game roles SSymphony can map Discord roles to. THIS list is the source of truth - roles are
/// defined here in code and CANNOT be created from the panel. Key = the role key the game checks via
/// symphony_has_ingame_role(); value = a human-readable description shown in the panel. Add roles here.
GLOBAL_LIST_INIT(symphony_ingame_roles, list(
	"whitelist" = "Required to join the round.",
))

/// Returns the defined in-game roles so SSymphony can populate its role-mapping UI (source of truth = game).
/datum/world_topic/symphony_ingame_roles
	keyword = "symphony_ingame_roles"
	require_comms_key = TRUE

/datum/world_topic/symphony_ingame_roles/Run(list/input)
	. = list()
	var/list/roles = list()
	for(var/key in GLOB.symphony_ingame_roles)
		roles += list(list("key" = key, "description" = GLOB.symphony_ingame_roles[key]))
	.["roles"] = roles
