"""Shared helpers for procedural hero builds (Blender 4.2, headless). Used by
src/heroes/models/<hero>/blender/build_<hero>.py via sys.path. Flat-colour materials (sRGB palette ->
linear), simple primitive builders, armature + distance skinning, NLA actions, GLB export, turnaround shots.
Twin Tails' script predates this module and keeps its own copies of the same helpers."""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix, Euler

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default

class Build:
    def __init__(self, prefix, palette):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.scene = bpy.context.scene
        self.prefix = prefix
        self.pal = palette
        self.mats = {}
        self.parts = []
        self.bones = {}
        self.rig = None
        self.body = None

    # ------------------------------------------------------------ materials
    @staticmethod
    def lin(x):
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    def mat(self, name):
        if name not in self.mats:
            m = bpy.data.materials.new(self.prefix + "_" + name)
            c = tuple(self.lin(x) for x in self.pal[name])
            m.diffuse_color = (*c, 1.0)
            m.use_nodes = True
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (*c, 1.0)
            b.inputs["Roughness"].default_value = 1.0
            self.mats[name] = m
        return self.mats[name]

    # ------------------------------------------------------------ primitives
    def obj(self, name, bm, material, bones, smooth=True):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new(name, me)
        self.scene.collection.objects.link(ob)
        ob.data.materials.append(self.mat(material))
        for p in ob.data.polygons:
            p.use_smooth = smooth
        self.parts.append((ob, bones))
        return ob

    @staticmethod
    def _frame(t):
        t = t.normalized()
        if abs(t.z) >= 0.9:
            x = Vector((1, 0, 0)); y = t.cross(x).normalized(); x = y.cross(t).normalized()
        else:
            x = Vector((0, 0, 1)).cross(t).normalized(); y = t.cross(x).normalized()
        return x, y

    def loft(self, name, rings, material, bones, n=12, cap0=True, cap1=True, arc=None, smooth=True):
        """rings: (center, rx, ry) ellipse sections along a path; arc=(a0,a1) deg -> open shell."""
        bm = bmesh.new(); loops = []
        for i, r in enumerate(rings):
            c, rx, ry = Vector(r[0]), r[1], r[2]
            a = Vector(rings[min(i + 1, len(rings) - 1)][0]) - Vector(rings[max(i - 1, 0)][0])
            if a.length < 1e-6:
                a = Vector((0, 0, -1))
            x, y = self._frame(a)
            cnt = n if arc is None else n + 1
            vs = []
            for k in range(cnt):
                th = 2 * math.pi * k / n if arc is None else math.radians(arc[0] + (arc[1] - arc[0]) * k / n)
                vs.append(bm.verts.new(c + x * (math.cos(th) * rx) + y * (math.sin(th) * ry)))
            loops.append(vs)
        for i in range(len(loops) - 1):
            a, b = loops[i], loops[i + 1]; m = len(a)
            for k in range(m if arc is None else m - 1):
                k2 = (k + 1) % m
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
        if arc is None:
            if cap0: bm.faces.new(list(reversed(loops[0])))
            if cap1: bm.faces.new(loops[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.obj(name, bm, material, bones, smooth)

    def ellipsoid(self, name, c, r, material, bones, seg=14, rings=9):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2])) + Vector(c)
        return self.obj(name, bm, material, bones)

    def rock(self, name, c, r, material, bones, seg=7, rings=5, rot=(0, 0, 0), seed=0, jitter=0.12):
        """Low-poly faceted stone (flat shaded), slightly irregular."""
        import random
        rnd = random.Random(seed)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        R = Euler([math.radians(a) for a in rot]).to_matrix()
        for v in bm.verts:
            k = 1.0 + rnd.uniform(-jitter, jitter)
            v.co = R @ Vector((v.co.x * r[0] * k, v.co.y * r[1] * k, v.co.z * r[2] * k)) + Vector(c)
        return self.obj(name, bm, material, bones, smooth=False)

    def box(self, name, c, size, material, bones, bevel=0.0, rot=(0, 0, 0), smooth=True):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect='EDGES')
        R = Euler([math.radians(a) for a in rot]).to_matrix()
        for v in bm.verts:
            v.co = R @ v.co + Vector(c)
        return self.obj(name, bm, material, bones, smooth)

    def prism(self, name, pts2d, depth, material, bones, xf=Matrix.Identity(4), smooth=False):
        """Extruded flat polygon: pts in the local XZ plane, extruded along local Y, then transformed by xf."""
        bm = bmesh.new()
        f = [bm.verts.new((p[0], -depth / 2, p[1])) for p in pts2d]
        b = [bm.verts.new((p[0], depth / 2, p[1])) for p in pts2d]
        bm.faces.new(list(reversed(f))); bm.faces.new(b)
        n = len(pts2d)
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((f[k], f[k2], b[k2], b[k]))
        bmesh.ops.triangulate(bm, faces=[fc for fc in bm.faces if len(fc.verts) > 4])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for v in bm.verts:
            v.co = xf @ v.co
        return self.obj(name, bm, material, bones, smooth)

    def crystal(self, name, c, h, r, material, bones, tilt=(0, 0, 0)):
        """Hexagonal crystal with a pointed top (amber gems)."""
        bm = bmesh.new()
        R = Euler([math.radians(a) for a in tilt]).to_matrix()
        base, mid = [], []
        for k in range(6):
            a = 2 * math.pi * k / 6
            base.append(bm.verts.new(Vector((math.cos(a) * r * 0.8, math.sin(a) * r * 0.8, 0))))
            mid.append(bm.verts.new(Vector((math.cos(a) * r, math.sin(a) * r, h * 0.7))))
        top = bm.verts.new(Vector((0, 0, h)))
        bm.faces.new(list(reversed(base)))
        for k in range(6):
            k2 = (k + 1) % 6
            bm.faces.new((base[k], base[k2], mid[k2], mid[k]))
            bm.faces.new((mid[k], mid[k2], top))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for v in bm.verts:
            v.co = R @ v.co + Vector(c)
        return self.obj(name, bm, material, bones, smooth=False)

    def decal(self, name, pts2d, c, material, bones, yaw=0.0, pitch=0.0):
        """Flat polygon in XZ facing -Y, rotated by pitch (about X) then yaw (about Z), placed at c."""
        bm = bmesh.new()
        vs = [bm.verts.new((p[0], 0.0, p[1])) for p in pts2d]
        bm.faces.new(vs)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        R = Matrix.Rotation(yaw, 3, 'Z') @ Matrix.Rotation(pitch, 3, 'X')
        for v in bm.verts:
            v.co = R @ v.co + Vector(c)
        return self.obj(name, bm, material, bones, smooth=False)

    @staticmethod
    def ellipse_pts(w, h, n=10):
        return [(math.cos(2 * math.pi * k / n) * w, math.sin(2 * math.pi * k / n) * h) for k in range(n)]

    @staticmethod
    def jag(pts, amp, n_per_edge, seed=1, edges=None):
        """Insert zig-zag points along polygon edges (ragged cloth / jagged blade)."""
        import random
        rnd = random.Random(seed)
        out = []
        m = len(pts)
        for i in range(m):
            a, b = Vector((*pts[i], 0)), Vector((*pts[(i + 1) % m], 0))
            out.append(pts[i])
            if edges is not None and i not in edges:
                continue
            d = b - a
            nrm = Vector((d.y, -d.x, 0)).normalized()
            for k in range(1, n_per_edge):
                t = k / n_per_edge
                p = a + d * t + nrm * (amp * (1 if k % 2 else -0.3) * rnd.uniform(0.6, 1.2))
                out.append((p.x, p.y))
        return out

    # ------------------------------------------------------------ armature + skin
    def begin_rig(self, name):
        arm = bpy.data.armatures.new(name)
        self.rig = bpy.data.objects.new(name, arm)
        self.scene.collection.objects.link(self.rig)
        bpy.context.view_layer.objects.active = self.rig
        bpy.ops.object.mode_set(mode='EDIT')
        self._eb = arm.edit_bones

    def bone(self, name, head, tail, parent=None, connect=False, roll=0.0):
        b = self._eb.new(name)
        b.head = Vector(head); b.tail = Vector(tail); b.roll = roll
        if parent:
            b.parent = self._eb[parent]; b.use_connect = connect
        self.bones[name] = (Vector(head), Vector(tail))
        return b

    def end_rig(self):
        bpy.ops.object.mode_set(mode='OBJECT')

    def _seg(self, p, a, b):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (a + ab * t - p).length

    def skin_and_join(self, mesh_name):
        for ob, cands in self.parts:
            for c in cands:
                if c not in ob.vertex_groups:
                    ob.vertex_groups.new(name=c)
            for v in ob.data.vertices:
                if len(cands) == 1:
                    ob.vertex_groups[cands[0]].add([v.index], 1.0, 'REPLACE'); continue
                ds = sorted((self._seg(v.co, *self.bones[c]), c) for c in cands)[:2]
                ws = [1.0 / max(d, 0.004) ** 4 for d, _ in ds]
                tot = sum(ws)
                for (d, c), w in zip(ds, ws):
                    if w / tot > 0.02:
                        ob.vertex_groups[c].add([v.index], w / tot, 'REPLACE')
        bpy.ops.object.select_all(action='DESELECT')
        for ob, _ in self.parts:
            ob.select_set(True)
        body = self.parts[0][0]
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        body.name = mesh_name; body.data.name = mesh_name
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.0002)
        bpy.ops.object.mode_set(mode='OBJECT')
        body.parent = self.rig
        body.modifiers.new("Armature", 'ARMATURE').object = self.rig
        self.body = body
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        print("TRIS", tris)
        return tris

    def marker(self, name, bone, pos):
        """Empty parented to a bone -> BoneAttachment3D child `name` in Godot (anchors: tips, muzzles)."""
        e = bpy.data.objects.new(name, None)
        self.scene.collection.objects.link(e)
        e.parent = self.rig; e.parent_type = 'BONE'; e.parent_bone = bone
        bpy.context.view_layer.update()
        e.matrix_world = Matrix.Translation(Vector(pos))
        return e

    # ------------------------------------------------------------ animation
    def begin_anim(self):
        bpy.context.view_layer.objects.active = self.rig
        bpy.ops.object.mode_set(mode='POSE')
        self.pb = self.rig.pose.bones
        for pb in self.pb:
            pb.rotation_mode = 'XYZ'

    def _key(self, frame, poses, loc=None):
        for pb in self.pb:
            pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0)
        for n, r in poses.items():
            self.pb[n].rotation_euler = [math.radians(a) for a in r]
        for n, l in (loc or {}).items():
            self.pb[n].location = l
        for pb in self.pb:
            pb.keyframe_insert("rotation_euler", frame=frame)
            pb.keyframe_insert("location", frame=frame)

    def action(self, name, frames, interp='BEZIER'):
        """frames: [(frame, {bone: (x,y,z) deg}, {bone: loc}?)]; names ending _loop loop in Godot."""
        self.rig.animation_data_create()
        act = bpy.data.actions.new(name)
        self.rig.animation_data.action = act
        for f, poses, *rest in frames:
            self._key(f, poses, rest[0] if rest else None)
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = interp
        tr = self.rig.animation_data.nla_tracks.new(); tr.name = name
        tr.strips.new(name, int(frames[0][0]), act)
        self.rig.animation_data.action = None
        return act

    def end_anim(self):
        for pb in self.pb:
            pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0)
        bpy.ops.object.mode_set(mode='OBJECT')

    # ------------------------------------------------------------ export + shots
    def export(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_animations=True, export_nla_strips=True,
                                  export_animation_mode='NLA_TRACKS', export_skins=True, export_apply=False,
                                  export_yup=True, export_materials='EXPORT', export_force_sampling=True)
        print("EXPORTED", path)

    def shots(self, out_dir, center_z, ortho, dist=8.0, views=(("front", 0), ("side", 90), ("three_quarter", 35)), elev=0.0):
        if not out_dir:
            return
        os.makedirs(out_dir, exist_ok=True)
        sc = self.scene
        sc.render.engine = 'BLENDER_WORKBENCH'
        sh = sc.display.shading
        sh.light = 'FLAT'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True
        sh.object_outline_color = (0, 0, 0); sh.show_cavity = False
        sc.render.resolution_x = 1000; sc.render.resolution_y = 1000
        sh.background_type = 'VIEWPORT'; sh.background_color = (1, 1, 1)
        sc.view_settings.view_transform = 'Standard'
        cd = bpy.data.cameras.new("cam"); cd.type = 'ORTHO'; cd.ortho_scale = ortho
        cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
        for nm, yaw in views:
            a = math.radians(yaw); e = math.radians(elev)
            cam.location = (dist * math.sin(a) * math.cos(e), -dist * math.cos(a) * math.cos(e), center_z + dist * math.sin(e))
            cam.rotation_euler = (math.radians(90) - e, 0, a)
            sc.render.filepath = os.path.join(out_dir, "blender_%s.png" % nm)
            bpy.ops.render.render(write_still=True)
            print("SHOT", sc.render.filepath)

    def pose_shots(self, out_dir, specs, center_z, ortho, dist=8.0):
        """specs: [(action, frame, yaw_deg, filename)] - renders posed frames (call after shots(); reuses camera)."""
        if not out_dir:
            return
        sc = self.scene
        ad = self.rig.animation_data
        for tr in ad.nla_tracks:
            tr.mute = True
        cam = sc.camera
        cam.data.ortho_scale = ortho
        for act, frame, yaw, fn in specs:
            ad.action = bpy.data.actions[act]
            sc.frame_set(frame)
            a = math.radians(yaw)
            cam.location = (dist * math.sin(a), -dist * math.cos(a), center_z)
            cam.rotation_euler = (math.radians(90), 0, a)
            sc.render.filepath = os.path.join(out_dir, fn)
            bpy.ops.render.render(write_still=True)
        ad.action = None
        for tr in ad.nla_tracks:
            tr.mute = False
        sc.frame_set(1)
