"""Run with Blender --background --python this_file. Coordinates authored in Godot axes."""
import bpy, math, os
from mathutils import Vector
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT, 'game/assets/models/edger_landing_deck')
os.makedirs(OUT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
def mat(name, color, metal, rough):
    m = bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    return m
paint=mat('Forest green powder coated frame',(.075,.19,.13),.7,.38)
steel=mat('Brushed galvanized ramp steel',(.48,.53,.56),.85,.32)
dark=mat('Oiled chain steel',(.075,.085,.095),.9,.27)
bright=mat('Machined pins and fasteners',(.36,.40,.43),.95,.22)
yellow=mat('Safety ochre drive guard',(.78,.36,.045),.65,.4)
def xyz(v): return (v[0],-v[2],v[1])
def finish(o,name,m):
    o.name=name; o.data.materials.append(m)
    return o
def box(name,pos,size,m,bevel=.003):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(pos)); o=bpy.context.object
    o.dimensions=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Fabricated edge radii','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,m)
def cyl(name,pos,r,length,m,axis='X',verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=length,location=xyz(pos))
    o=bpy.context.object
    if axis=='X': o.rotation_euler[1]=math.pi/2
    elif axis=='Z': o.rotation_euler[0]=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m)
TRACKS=[-2.75,-1.375,0,1.375,2.75]
for z in [-.65,1.35,3.35]:
    box('Crossmember', (0,-.40,z),(5.95,.18,.12),paint)
    for x in [-2.7,2.7]:
        box('Square tube leg',(x,-1.04,z),(.12,1.36,.12),paint)
        box('Anchor foot',(x,-1.74,z),(.30,.025,.28),steel)
        for dx in [-.10,.10]: cyl('Anchor bolt',(x+dx,-1.715,z),.018,.035,bright,'Y',6)
for x in TRACKS:
    box('Chain guide rail',(x,-.075,1.35),(.12,.10,4),paint)
    box('Return guide',(x,-.315,1.35),(.10,.035,4),dark)
    for z in [-.65,3.35]:
        box('Pillow bearing',(x-.11,-.16,z),(.06,.14,.18),paint)
        for dz in [-.065,.065]: cyl('Bearing bolt',(x-.11,-.085,z+dz),.012,.02,bright,'Y',6)
        cyl('Sprocket hub',(x,-.16,z),.075,.16,bright)
        cyl('Sprocket',(x,-.16,z),.125,.075,dark,verts=24)
        for k in range(16):
            a=math.tau*k/16
            tooth=box('Sprocket tooth',(x,-.16+.133*math.cos(a),z+.133*math.sin(a)),(.08,.025,.024),dark,.001)
            tooth.rotation_euler[0]=a
for z in [-.65,3.35]: cyl('Common drive shaft',(0,-.16,z),.035,6,bright)
box('Gear reducer',(3.02,-.22,3.35),(.36,.32,.32),paint)
cyl('Electric motor',(3.32,-.22,3.35),.15,.38,paint)
for x in [3.18+i*.035 for i in range(9)]: cyl('Motor cooling fin',(x,-.22,3.35),.163,.009,paint)
box('Drive coupling guard',(2.95,-.13,3.35),(.25,.22,.38),yellow)
# Short 0.8 m landing lane only. Each plate climbs along incoming +X.
for i,x1 in enumerate(TRACKS):
    x0=-3.10 if i==0 else TRACKS[i-1]+.075
    x1-=.075
    y0=-.09; y1=-.006
    length=math.hypot(x1-x0,y1-y0)
    ramp=box('LandingRamp_%02d'%i,((x0+x1)/2,(y0+y1)/2-.004,0),(length,.008,.8),steel,.001)
    ramp.rotation_euler[1]=-math.atan2(y1-y0,x1-x0)
    for z in [-.34,.34]:
        box('Ramp support bracket',(x1-.08,-.12,z),(.10,.19,.04),paint)
# Keep each common shaft and its sprockets independently animatable.
rotating=[]
for i,z in enumerate([-.65,3.35]):
    objs=[o for o in bpy.context.scene.objects if o.name.startswith(('Sprocket','Common drive shaft')) and abs(o.location.y+z)<.2]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join()
    shaft=objs[0];shaft.name='DriveShaft_%d'%i
    bpy.context.scene.cursor.location=xyz((0,-.16,z));bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    rotating.append(shaft)
# Combine static meshes by material to limit draw calls.
for material in [paint,steel,dark,bright,yellow]:
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.active_material==material and o not in rotating]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join()
    objs[0].name='Structure_'+material.name.split()[0]
static=list(bpy.context.scene.objects)
def export(path,objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',use_selection=True,export_yup=True)
export(os.path.join(OUT,'landing_deck_frame.glb'),static)
# One detailed reusable link; in Godot a MultiMesh circulates these around each loop.
before=set(bpy.context.scene.objects)
for x in [-.046,.046]: box('Link side plate',(x,-.015,0),(.012,.028,.087),dark,.005)
for z in [-.031,.031]:
    cyl('Link roller',(0,-.015,z),.015,.080,bright)
    cyl('Rivet pin',(0,-.015,z),.007,.115,dark)
parts=list(set(bpy.context.scene.objects)-before)
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join(); link=parts[0]
bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
link.name='RollerChainLink'
export(os.path.join(OUT,'roller_chain_link.glb'),[link])
loop=8+math.tau*.145
count=round(loop/.085)
def point(s):
    r=.145
    if s<4:return (1.35-2+s,-.015,0)
    s-=4
    if s<math.pi*r:
        a=s/r;return (3.35+r*math.sin(a),-.16+r*math.cos(a),a)
    s-=math.pi*r
    if s<4:return (3.35-s,-.305,math.pi)
    a=(s-4)/r+math.pi
    return (-.65+r*math.sin(a),-.16+r*math.cos(a),a)
# Full editable assembly in .blend; the GLB uses instanced links at runtime.
for ti,x in enumerate(TRACKS):
    for j in range(count):
        z,y,a=point(j*loop/count)
        o=bpy.data.objects.new('Chain_%d_Link_%03d'%(ti,j),link.data)
        bpy.context.collection.objects.link(o);o.location=xyz((x,y+.015,z));o.rotation_euler[0]=a
bpy.data.objects.remove(link,do_unlink=True)
bpy.context.scene.unit_settings.system='METRIC'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__),'edger_landing_deck.blend'))
print('LANDING_DECK_BUILD_OK',len(bpy.context.scene.objects),'objects',count,'links per chain')
