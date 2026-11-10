function check_original_isolation(repo)
if nargin < 1, repo = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
% The original chipmunk protocol resolves its own functions, with the Solo tree in the repo.
% Works for both layouts: protocol at the repo root (old) or in repo/chipmunk (new).
orig = repo; if exist(fullfile(repo,'chipmunk','chipmunk.m'),'file'), orig = fullfile(repo,'chipmunk'); end
addpath(orig); addpath(genpath(fullfile(orig,'Functions')));
assert(strcmp(which('chipmunk'),fullfile(orig,'chipmunk.m')),'chipmunk resolves to %s',which('chipmunk'));
assert(~contains(path,fullfile(repo,'chipmunk_solo')),'Solo tree is on the original protocol path');
solo=dir(fullfile(repo,'chipmunk_solo','Functions','**','*.m'));
origf=dir(fullfile(orig,'Functions','**','*.m'));
shared=intersect({solo.name},{origf.name});
for k=1:numel(shared)
    [~,n]=fileparts(shared{k}); w=which(n);
    assert(startsWith(w,fullfile(orig,'Functions')),'%s resolves to %s',n,w);
end
files=[dir(fullfile(orig,'*.m'));origf];
for k=1:numel(files)  % every original file still parses
    info=checkcode(fullfile(files(k).folder,files(k).name),'-struct');
    bad=info(arrayfun(@(i) contains(i.message,{'Parse error','Invalid syntax'}),info));
    assert(isempty(bad),'%s: %s',files(k).name,strjoin({bad.message},'; '));
end
fprintf('ORIGINAL_ISOLATION_PASS (%s): %d shared function names resolve to the original tree, %d files parse\n',orig,numel(shared),numel(files));
end
