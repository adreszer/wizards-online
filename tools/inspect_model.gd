extends SceneTree
## Dev tool: prints what Godot imported from a model (node tree, AABB, surfaces,
## triangle counts, materials, textures). Use it to size the wrapper .tscn for a
## new environment asset. Run:
##   godot --headless --path . -s tools/inspect_model.gd -- res://assets/models/environment/modular/wall_plain.glb


func _init() -> void:
	var path := "res://assets/models/environment/modular/wall_plain.glb"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			path = arg
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Could not load %s" % path)
		quit(1)
		return
	var root := packed.instantiate()
	print("== %s" % path)
	_dump(root, 0)
	var aabb := AABB()
	var first := true
	var tris := 0
	for mi in _meshes(root):
		var xf := _relative_transform(mi, root)
		var box := xf * mi.mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			tris += count / 3
			print("  surface %d: %d tris, format 0x%x" % [s, count / 3, mi.mesh.surface_get_format(s)])
			_dump_material(mi.mesh.surface_get_material(s))
	print("== merged AABB (scene units): position %s size %s end %s" % [aabb.position, aabb.size, aabb.end])
	print("== centre %s, total triangles %d" % [aabb.get_center(), tris])
	root.free()
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + "%s (%s)" % [node.name, node.get_class()]
	if node is Node3D:
		line += " xf=%s" % (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		line += " mesh=%s (%s) surfaces=%d" % [mi.mesh.resource_name, mi.mesh.get_class(), mi.mesh.get_surface_count()]
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _relative_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xf = (current as Node3D).transform * xf
		current = current.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf


func _dump_material(mat: Material) -> void:
	if mat == null:
		print("    material: <none>")
		return
	print("    material: %s (%s)" % [mat.resource_name, mat.get_class()])
	var m := mat as BaseMaterial3D
	if m == null:
		return
	print("      transparency=%d cull=%d shading=%d albedo=%s metallic=%.2f roughness=%.2f" % [
		m.transparency, m.cull_mode, m.shading_mode, m.albedo_color, m.metallic, m.roughness])
	print("      metallic_texture_channel=%d roughness_texture_channel=%d" % [m.metallic_texture_channel, m.roughness_texture_channel])
	for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS,
			BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
		var tex := m.get_texture(slot)
		if tex != null:
			print("      texture slot %d: %s %dx%d %s" % [slot, tex.resource_name, tex.get_width(), tex.get_height(), tex.get_class()])
	print("      normal_enabled=%s ao_enabled=%s emission_enabled=%s" % [m.normal_enabled, m.ao_enabled, m.emission_enabled])
