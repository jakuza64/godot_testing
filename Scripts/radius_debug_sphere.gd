class_name RadiusDebugSphere
extends MeshInstance3D
## A translucent sphere for visualising a radius in world space. Add it as a child
## of any node, then call show_at(). Use hide() to hide it again.


func _init(color := Color(1.0, 0.3, 0.2, 0.25)) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # still visible from inside
	material.albedo_color = color

	# A unit sphere, scaled to the radius in show_at().
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = material
	mesh = sphere

	top_level = true # world-space placement, regardless of the parent's transform
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Must be called while the sphere is inside the scene tree.
func show_at(center: Vector3, radius: float) -> void:
	global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radius), center)
	visible = true
