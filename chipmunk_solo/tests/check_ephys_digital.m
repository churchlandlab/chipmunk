function check_ephys_digital()
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; cleanup=onCleanup(@() path(oldPath));
addpath(genpath(fullfile(root,'Functions')));
% Analog channel 0, packed XD, packed SY. Preserve signed 16-bit patterns.
s=struct('data',[99 0 0; 99 1 64; 99 2048 -32704; 99 4095 0], ...
    'channels',[0 1 2],'nXA',1,'nDW',1,'nSY',1);
[d,labels]=oneBoxDigitalLines(s);
assert(isequal(size(d),[4 13]));
assert(isequal(d(:,1)',logical([0 1 0 1])));
assert(isequal(d(:,12)',logical([0 0 1 1])));
assert(isequal(d(:,13)',logical([0 1 1 0])));
assert(all(d(4,1:12)) && ~any(d(1,:)));
assert(strcmp(labels{1},'XD0') && strcmp(labels{12},'XD11'));
s.data=s.data(:,[3 1]);s.channels=[2 0];
[d,labels]=oneBoxDigitalLines(s);
assert(size(d,2)==1 && strcmp(labels{1},'Sync (SY6)'));
s.data=zeros(0,3);s.channels=0:2;
[d,labels]=oneBoxDigitalLines(s);
assert(isequal(size(d),[0 13]) && numel(labels)==13);
s.data=zeros(2,1);s.channels=0;s.nDW=0;s.nSY=0;
[d,labels]=oneBoxDigitalLines(s);
assert(isempty(d) && isempty(labels));
disp('PASS: all 12 OneBox digital inputs, sync, signed words and missing/empty channels');
end
