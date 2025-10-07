# Module Map

| Path | Type | Public API | Depends on | Notes |
|------|------|------------|------------|-------|
| ReplicatedStorage/Modules/PetCatalog.lua | module | `Get(id)`, `All()` | — | Central pet data |
| ReplicatedStorage/Modules/PetService.lua | module | `GetOwned(player)`, `Add(player, id)`, `Equip(player, id)` | PetCatalog | Inventory logic |
| ServerScriptService/RebirthHandler.server.lua | server | — | PlayerData | Handles rebirth event |
| StarterPlayer/StarterPlayerScripts/UI/Inventory.client.lua | client | — | PetService | Renders inventory UI |
| ReplicatedStorage/Modules/Rarities.lua | module | — | Rarities | Central rarities info |
