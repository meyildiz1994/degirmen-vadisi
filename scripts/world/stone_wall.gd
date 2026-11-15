class_name StoneWall
extends RefCounted
## Taş duvar örücü: üst üste dizilmiş, rengi değişen bloklar (değirmen gövdesi ve onarım sıraları).
## Satır 0.5 m. keep < 1 ise bazı taşlar eksik (yıkık sıra).

const ROW_H := 0.5
const WALL_T := 0.45


static func stone_color(rng: RandomNumberGenerator, base := Palette.STONE) -> Color:
	return base.lerp(Palette.STONE_DARK, rng.randf() * 0.6).lerp(Palette.SAND, rng.randf() * 0.2)


## r0..r1 (dahil) satırlarını ör. fresh: yeni örülmüş, daha açık ve verilen renge çalan taşlar.
static func rows(kit: MeshKit, rng: RandomNumberGenerator, start: Vector3, along: Vector3, length: float,
		r0: int, r1: int, keep := 1.0, tint := Color(0, 0, 0, 0)) -> void:
	var dir := along.normalized()
	var yaw := atan2(dir.x, dir.z)
	for r in range(r0, r1 + 1):
		var x := 0.0
		var offset := 0.35 if r % 2 == 1 else 0.0
		var first := true
		while x < length - 0.01:
			var w := minf(rng.randf_range(0.6, 1.1) - (offset if first else 0.0), length - x)
			w = maxf(w, 0.2)
			first = false
			var c := stone_color(rng)
			if tint.a > 0.0:
				c = c.lerp(tint, 0.35).lightened(0.08)
			if rng.randf() <= keep:
				var center := start + dir * (x + w * 0.5) + Vector3(0, r * ROW_H + ROW_H * 0.5, 0)
				kit.box(center, Vector3(WALL_T + rng.randf_range(-0.03, 0.05), ROW_H - 0.02, w - 0.04), c, Vector3(0, yaw, 0))
			x += w
