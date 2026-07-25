/obj/structure/flora/tree/harvest(mob/living/user, product_amount_multiplier)
	. = ..()
	var/turf/my_turf = get_turf(src)
	if(has_gravity(my_turf)) // If a tree falls in the forest, it makes a sound unless it doesn't have gravity.
		playsound(my_turf, 'sound/effects/meteorimpact.ogg', 100 , FALSE, extrarange = TREE_FALL_EXTRARANGE)
	var/obj/structure/flora/tree/stump/new_stump = new stump_type(my_turf) // NOVA EDIT CHANGE - Variable tree stumps - ORIGINAL: var/obj/structure/flora/tree/stump/new_stump = new(my_turf)
	new_stump.name = "[name] stump"