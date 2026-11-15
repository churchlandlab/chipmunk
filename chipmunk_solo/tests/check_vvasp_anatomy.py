"""Run with the existing VVASP environment (numpy, tifffile, pyvista)."""
import sys
from pathlib import Path
import numpy as np
import pyvista as pv
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from export_vvasp_anatomy import rotation,voxel_coordinates,region_segments,atlas_transform

# Independent VTK rotations reproduce the legacy VVASP mesh transform.
raw=np.array([[10.,20.,30.],[40.,50.,60.]])
mesh=pv.PolyData(raw.copy());mesh.rotate_y(90,inplace=True);mesh.rotate_x(-90,inplace=True);mesh.rotate_x(5,inplace=True)
record={'atlas':{'name':'allen_mouse_25um'},'vvasp_commit_version':'883c271'}
b,r,s,source=atlas_transform(record,{'bregma_locations':{'allen_mouse_25um':[0,0,0]}})
assert np.allclose(voxel_coordinates(mesh.points,b,r,s,np.ones(3)),raw)
# Preserve explicit nonuniform scaling and bregma rather than using defaults.
b=np.array([2.,3.,4.]);s=np.array([.952,1.031,.885]);r=rotation([-90,5,-90])
physical=((raw-b)*1.)@r.T*s
assert np.allclose(voxel_coordinates(physical,b,r,s,np.ones(3)),raw)
# Distances stay in physical shank microns; outside points are not edge-clipped.
a=np.ones((2,2,2),int);points=np.array([[-1,0,0],[0,0,0],[1,0,0],[2,0,0]])
segments,ids=region_segments(points,np.arange(4),a,{1:{'acronym':'TEST','rgb_triplet':[1,2,3]}},(np.zeros(3),np.eye(3),np.ones(3)),np.ones(3))
assert ids.tolist()==[0,1,1,0]
assert [(x['startUm'],x['endUm'],x['region']) for x in segments]==[(0,.5,'outside'),(.5,2.5,'TEST'),(2.5,3,'outside')]
assert np.allclose(np.linalg.norm(np.diff((np.arange(4)[:,None]*np.array([[250.,0,0]]))@rotation([131,0,-20],'yxz').T,axis=0),axis=1),250)
try:
 atlas_transform({'atlas':{'name':'allen_mouse_25um'},'vvasp_commit_version':'unknown'},{})
 raise AssertionError('Unknown legacy transform accepted')
except ValueError:pass
print('PASS: VVASP legacy VTK transform, explicit scaling/bregma, region boundaries and physical shank distances')
