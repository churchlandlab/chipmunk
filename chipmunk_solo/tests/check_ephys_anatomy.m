function check_ephys_anatomy()
root=fileparts(fileparts(mfilename('fullpath')));oldPath=path;
cleanup=onCleanup(@() path(oldPath));addpath(genpath(fullfile(root,'Functions')));
r=struct('startUm',0,'endUm',100,'region','TEST','rgb',[10 20 30]);
p=struct('formatVersion',1,'subject','FakeSubject','placementKind','surgery plan', ...
 'nShanks',4,'provenance',struct('sourceSHA256',repmat('a',1,64)),'shanks',[]);
for k=1:4,p.shanks(k).shankId=k-1;p.shanks(k).segments=r;end
commands=vvaspAnatomyCommands(p,'(0,4,NP2010)','FakeSubject');
assert(numel(commands)==4 && strcmp(commands{1},'[0,0](0.000,100.000,10,20,30,TEST)'));
fig=figure('Visible','off');figCleanup=onCleanup(@() delete(fig));ax=axes(fig);
plotProfile=p;
for k=1:4,plotProfile.shanks(k).segments.endUm=3000;end
bands=plotSpikeGLXSurgeryPlan(ax,plotProfile,@(id,r) setappdata(fig,'picked',{id,r.region}));
assert(numel(bands)==4 && isequal(ax.XTick,0:3) && strcmp(ax.YDir,'normal'));
boundaries=findobj(ax,'Tag','BankBoundary');assert(numel(boundaries)==4);
for k=1:4,assert(isequal(boundaries(k).YData,[2500 2500]) && strcmp(boundaries(k).LineStyle,'--'));end
callback=bands(1).ButtonDownFcn;callback(bands(1),[]);
assert(isequal(getappdata(fig,'picked'),{0,'TEST'}));
assert(contains(ax.Title.String,'planned anatomy'));
clear figCleanup
for data={'()','(0,1,NP1000)','(0,4,NP2010)(1,4,NP2010)'}
 try,vvaspAnatomyCommands(p,data{1},'FakeSubject');error('Test:Expected','Expected rejection');
 catch e,assert(startsWith(e.identifier,'chipmunk_solo:Anatomy'));end
end
try,vvaspAnatomyCommands(p,'(0,4,NP2010)','DifferentSubject');error('Test:Expected','Expected rejection');
catch e,assert(strcmp(e.identifier,'chipmunk_solo:AnatomySubject'));end
p.shanks(1).segments.region=sprintf('bad\ncommand');
try,vvaspAnatomyCommands(p,'(0,4,NP2010)','FakeSubject');error('Test:Expected','Expected rejection');
catch e,assert(~strcmp(e.identifier,'Test:Expected'));end
fprintf('PASS: subject/probe/shank matching, native anatomy formatting and unsafe-label rejection\n');
end
