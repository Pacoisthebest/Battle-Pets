local ArenaCatalog = {
	red_orb =   { Name = "Red Orb", XP = 10, SpawnLimit = 50, RespawnTime = 5},
	blue_orb =   { Name = "Blue Orb", XP = 25, SpawnLimit = 10, RespawnTime = 5},
	yellow_orb =   { Name = "Yellow Orb", XP = 5000, SpawnLimit = 50, RespawnTime = 5},
}

function ArenaCatalog.All()
	return ArenaCatalog
end

function ArenaCatalog.Get(id)
	return ArenaCatalog[id]
end

return ArenaCatalog
