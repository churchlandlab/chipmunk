function check_shared_vvasp()
root=fileparts(fileparts(mfilename('fullpath')));oldPath=path;
pathCleanup=onCleanup(@() path(oldPath));addpath(genpath(fullfile(root,'Functions')));
folder=tempname;mkdir(fullfile(folder,'experiments'));mkdir(fullfile(folder,'anatomy'));
cleanup=onCleanup(@() rmdir(folder,'s'));
source=fullfile(folder,'experiments','FakeSubject_chronic_NP2.json');
raw='{"info":"FakeSubject"}';write(source,raw);
digest=java.security.MessageDigest.getInstance('SHA-256');digest.update(int8(raw));
hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
p=struct('subject','FakeSubject','provenance',struct('sourceFile','FakeSubject_chronic_NP2.json','sourceSHA256',hash));
file=fullfile(folder,'anatomy','FakeSubject.json');write(file,jsonencode(p));
loaded=loadSpikeGLXSurgeryPlan(folder,'FakeSubject','localhost');
assert(strcmp(loaded.provenance.sourceSHA256,hash) && strcmp(loaded.provenance.sourceDirectory,folder));
assert(isempty(loadSpikeGLXSurgeryPlan(folder,'MissingSubject','localhost')));
write(source,'{"info":"changed"}');reject(folder,'source changed');
write(source,raw);p.provenance.sourceFile='../outside.json';write(file,jsonencode(p));reject(folder,'filename');
p.provenance.sourceFile='FakeSubject_chronic_NP2.json';p.subject='OtherSubject';write(file,jsonencode(p));reject(folder,'another subject');
fprintf('PASS: shared VVASP source matching, provenance, missing subjects and stale/unsafe record rejection\n');
end
function write(path,text)
fid=fopen(path,'w');cleanup=onCleanup(@() fclose(fid));fwrite(fid,text);
end
function reject(folder,message)
try,loadSpikeGLXSurgeryPlan(folder,'FakeSubject','localhost');error('Test:Accepted','Unsafe plan accepted');
catch e,assert(~strcmp(e.identifier,'Test:Accepted') && contains(e.message,message));end
end
