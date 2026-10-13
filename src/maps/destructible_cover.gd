class_name DestructibleCover
extends StaticBody3D
## A map block of kind "cover" with "hp" in the map JSON. Still a solid StaticBody3D (meta kind = "cover",
## name cover_NN) so bots treat it as cover; it carries its own outline hull (child), so freeing the node
## removes collision, visuals and outline together. Damage is decided on the authority only (see MapDestruction).

var block_id := -1        ## index in the map JSON "blocks" array (deterministic on host and clients)
var max_hp := 100.0
var hp := 100.0
var destruction = null    ## MapDestruction (map root child "Destruction")

## Same signature as Hero.take_damage, so weapon/aoe code can hit either. Host/offline only; 0 on clients.
func take_damage(amount: float, source = null, _pos := Vector3.ZERO, _kind := "", _ability_id := "") -> float:
    return apply_damage(amount, source)

func apply_damage(amount: float, source = null) -> float:
    if destruction == null or not destruction.is_authority() or hp <= 0.0 or amount <= 0.0:
        return 0.0
    var applied := minf(amount, hp)
    hp -= applied
    if hp <= 0.0:
        destruction._break(self, source)
    return applied
