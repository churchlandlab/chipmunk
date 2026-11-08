#!/usr/bin/env python3
"""Export planned VVASP shank anatomy for SpikeGLX, without changing source files."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import numpy as np
import tifffile


def rotation(angles, order='xyz'):
    x,y,z=np.deg2rad(angles)
    rx=np.array([[1,0,0],[0,np.cos(x),-np.sin(x)],[0,np.sin(x),np.cos(x)]])
    ry=np.array([[np.cos(y),0,np.sin(y)],[0,1,0],[-np.sin(y),0,np.cos(y)]])
    rz=np.array([[np.cos(z),-np.sin(z),0],[np.sin(z),np.cos(z),0],[0,0,1]])
    matrices={'x':rx,'y':ry,'z':rz}
    return matrices[order[2]]@matrices[order[1]]@matrices[order[0]]


def atlas_transform(record, preferences):
    a=record['atlas']
    if all(k in a for k in ['bregma_location','rotation_angles','scaling']):
        return np.array(a['bregma_location']),rotation(a['rotation_angles']),np.array(a['scaling']),'experiment file'
    # This older VVASP version rotated meshes Y90, X-90, then X5, without scaling.
    if record.get('vvasp_commit_version')=='883c271':
        b=preferences['bregma_locations'][a['name']]
        return np.array(b),rotation([-85,90,0],'yxz'),np.ones(3),'VVASP 883c271 + saved bregma preferences'
    raise ValueError('Missing atlas transform for an unsupported VVASP version')


def voxel_coordinates(points, bregma, matrix, scaling, resolution):
    assert np.all(np.isfinite(points)) and np.all(scaling>0)
    return ((np.asarray(points)/scaling)@matrix+bregma*resolution)/resolution


def region_segments(points, distances, annotation, structures, transform, resolution):
    coords=np.rint(voxel_coordinates(points,*transform,resolution)).astype(int)
    valid=np.all((coords>=0)&(coords<np.array(annotation.shape)),axis=1)
    ids=np.zeros(len(points),dtype=np.int64)
    ids[valid]=annotation[tuple(coords[valid].T)]
    starts=np.r_[0,np.flatnonzero(np.diff(ids))+1]
    edges=np.r_[0,(distances[starts[1:]-1]+distances[starts[1:]])/2,distances[-1]]
    result=[]
    for i,start in enumerate(starts):
        region=structures.get(int(ids[start]),{'acronym':'outside','rgb_triplet':[170,170,170]})
        name=region['acronym']
        if not re.fullmatch(r'[A-Za-z0-9_./ -]+',name):raise ValueError('Unsafe region label: '+name)
        result.append({'startUm':float(edges[i]),'endUm':float(edges[i+1]),'region':name,'rgb':region['rgb_triplet']})
    return result,ids


def export_record(source, geometry_path, prefs_path, atlas_dir, annotation, structures):
    raw=source.read_bytes();record=json.loads(raw)
    subject=source.stem.split('_')[0]
    if not re.fullmatch(r'GRB(?:\d{3}|D\d+)',subject):raise ValueError('Not a mouse surgery record: '+source.name)
    probes=[p for p in record['probes'] if p.get('active',True)]
    if len(probes)!=1 or probes[0]['info']!=subject:raise ValueError('Expected one matching active probe')
    probe=probes[0]
    if not probe['probetype'].startswith(('NP2 chronic holder','NP2a chronic holder')):
        raise ValueError('Unsupported probe geometry: '+probe['probetype'])
    geometry=json.loads(geometry_path.read_text())['NP24']
    prefs=json.loads(prefs_path.read_text());meta=json.loads((atlas_dir/'metadata.json').read_text())
    if record['atlas']['name']!='allen_mouse_25um' or meta['name']!='allen_mouse':raise ValueError('Unexpected atlas')
    resolution=np.array(meta['resolution']);bregma,matrix,scaling,origin=atlas_transform(record,prefs)
    transform=(bregma,matrix,scaling)
    tip=np.array([probe['tip'][k] for k in ['ML','AP','DV']],float)
    angles=[probe['angles'][k] for k in ['elevation','spin','azimuth']]
    probe_rotation=rotation(angles,'yxz')
    direction=probe_rotation[:,1]
    offsets=np.array(geometry['shank_offsets_um'],float)
    dimensions=np.array(geometry['shank_dims_um'],float)
    offsets[:,0]+=dimensions[:,0]/2
    shank_tips=offsets@probe_rotation.T+tip
    shanks=[]
    for i,position in enumerate(shank_tips):
        distance=np.linspace(0,dimensions[i,1],round(dimensions[i,1]/10)+1)
        segments,_=region_segments(position+distance[:,None]*direction,distance,annotation,structures,transform,resolution)
        shanks.append({'shankId':i,'tipMLAPDVum':position.tolist(),'segments':segments})
    distance=np.linspace(0,10000,1001)
    _,ids=region_segments(tip+distance[:,None]*direction,distance,annotation,structures,transform,resolution)
    inside=np.flatnonzero(ids!=0)
    surface=float(distance[inside[-1]]) if len(inside) else None
    recorded_depth=probe.get('depth_along_probe_axis')
    if recorded_depth is not None and (surface is None or abs(surface-recorded_depth)>100):
        raise ValueError('Atlas surface does not agree with recorded insertion depth within 100 um')
    provenance={'sourceFile':source.name,'sourceSHA256':hashlib.sha256(raw).hexdigest(),
        'vvaspCommit':record['vvasp_commit_version'],'atlasVersion':meta['version'],
        'atlasName':record['atlas']['name'],'atlasTransformSource':origin,
        'bregmaVoxels':bregma.tolist(),'rotationMatrix':matrix.tolist(),'scaling':scaling.tolist(),
        'geometrySHA256':hashlib.sha256(geometry_path.read_bytes()).hexdigest(),
        'preferencesSHA256':hashlib.sha256(prefs_path.read_bytes()).hexdigest(),
        'samplingStepUm':10,'sourceDepthUm':probe.get('depth_along_probe_axis'),'sampledSurfaceDepthUm':surface}
    return {'formatVersion':1,'subject':subject,'placementKind':'surgery plan','probeType':probe['probetype'],
        'nShanks':len(shanks),'provenance':provenance,'shanks':shanks}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiments',type=Path,default=Path.home()/'vvasp/experiments')
    parser.add_argument('--atlas',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();base=args.experiments.parent
    annotation=tifffile.imread(args.atlas/'annotation.tiff')
    structures={x['id']:x for x in json.loads((args.atlas/'structures.json').read_text())}
    args.output.mkdir(parents=True,exist_ok=True)
    manifest=[];skipped=[]
    for source in sorted(args.experiments.glob('GRB*_*.json')):
        try:
            profile=export_record(source,base/'probe_geometries.json',base/'preferences.json',args.atlas,annotation,structures)
        except ValueError as error:
            skipped.append({'sourceFile':source.name,'reason':str(error)})
            continue
        output=args.output/(profile['subject']+'.json')
        output.write_text(json.dumps(profile,indent=2)+'\n')
        p=profile['provenance'];manifest.append({'subject':profile['subject'],'shanks':profile['nShanks'],
            'sourceDepthUm':p['sourceDepthUm'],'sampledSurfaceDepthUm':p['sampledSurfaceDepthUm'],
            'sourceSHA256':p['sourceSHA256']})
    (args.output/'manifest.json').write_text(json.dumps({'exported':manifest,'skipped':skipped},indent=2)+'\n')
    print(json.dumps({'exported':manifest,'skipped':skipped},indent=2))

if __name__=='__main__':main()
