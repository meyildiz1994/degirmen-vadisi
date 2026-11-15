class_name ValleyShape
extends RefCounted
## Vadinin analitik şekli: zemin yüksekliği, dere hattı, su seviyesi.
## Arazi mesh'i, su, bitki örtüsü ve yapılar hep aynı fonksiyonları kullanır;
## böylece her şey zemine tam oturur.

const HALF_SIZE := 30.0          ## Oynanabilir alan: 60x60 birim
const PLATEAU_HEIGHT := 4.5      ## Kuzeydeki şelale platosunun yüksekliği
const WATER_LEVEL := -0.35       ## Vadi tabanındaki su yüzeyi
const BED_DEPTH := 0.8           ## Su yüzeyinin altındaki dere yatağı derinliği
const SEED := 1907

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite


static func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = SEED + 11
	_detail.frequency = 0.21


## Dere merkezinin x koordinatı (dere kuzeyden güneye, z ekseni boyunca akar).
static func river_x(z: float) -> float:
	return 1.5 + 3.2 * sin(z * 0.085 + 0.6) + 1.1 * sin(z * 0.21 + 2.0)


## Derenin yarı genişliği; şelalenin dibinde küçük bir gölet oluşur.
static func river_half_width(z: float) -> float:
	var pond := 2.0 * exp(-pow((z + 18.8) / 2.6, 2.0))
	return 1.6 + 0.35 * sin(z * 0.31 + 1.0) + pond


## 0: vadi tabanı, 1: kuzey platosu (arazi için yumuşak geçiş).
static func plateau_weight(z: float) -> float:
	return 1.0 - smoothstep(-23.2, -20.6, z)


## Su yüzeyi yüksekliği. Platodan vadiye geçiş dik olduğu için şelale oluşur.
static func water_y(z: float) -> float:
	var t := 1.0 - smoothstep(-22.7, -21.5, z)
	return WATER_LEVEL + PLATEAU_HEIGHT * t


static func distance_to_river(x: float, z: float) -> float:
	return absf(x - river_x(z))


## Dereden bağımsız zemin yüksekliği.
static func base_height(x: float, z: float) -> float:
	_ensure_noise()
	var d := distance_to_river(x, z)
	var rough := 0.4 + 0.6 * smoothstep(3.0, 10.0, d)
	var h := 0.4 + _noise.get_noise_2d(x, z) * 0.85 * rough
	# Vadinin doğu ve batı kenarları yükselir, güney kenarı hafifçe kalkar.
	h += smoothstep(17.0, 31.0, absf(x)) * 4.2
	h += smoothstep(21.0, 31.0, z) * 2.2
	h += plateau_weight(z) * PLATEAU_HEIGHT
	return h


## Dere yatağının zemine ne kadar oyulduğu (0..1).
static func carve_weight(x: float, z: float) -> float:
	var d := distance_to_river(x, z)
	var w := river_half_width(z)
	return 1.0 - smoothstep(w * 0.55, w + 2.0, d)


static func height(x: float, z: float) -> float:
	var h := base_height(x, z)
	var bed := water_y(z) - BED_DEPTH
	return lerpf(h, minf(h, bed), carve_weight(x, z))


static func normal(x: float, z: float) -> Vector3:
	var e := 0.25
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


static func detail_noise(x: float, z: float) -> float:
	_ensure_noise()
	return _detail.get_noise_2d(x, z)


## Patikalar: atölye → köprü → demir damarı ve atölye → değirmen.
static func path_points() -> Array[PackedVector2Array]:
	var bridge_z := 8.0
	var bx := river_x(bridge_z)
	var mill_z := -8.0
	var mx := river_x(mill_z)
	return [
		PackedVector2Array([Vector2(-11.0, 5.5), Vector2(-6.0, 8.5), Vector2(bx - 3.6, bridge_z)]),
		PackedVector2Array([Vector2(bx + 3.6, bridge_z), Vector2(bx + 8.0, 10.0), Vector2(15.0, 13.0)]),
		PackedVector2Array([Vector2(-6.0, 8.5), Vector2(-5.0, 0.0), Vector2(mx - 6.0, mill_z + 1.5)]),
	]


static func distance_to_path(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for line in path_points():
		for i in range(line.size() - 1):
			var c := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
			best = minf(best, p.distance_to(c))
	return best
