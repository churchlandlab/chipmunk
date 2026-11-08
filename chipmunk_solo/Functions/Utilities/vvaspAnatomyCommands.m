function commands = vvaspAnatomyCommands(profile, probeList, subject)
% Convert a verified surgery plan to native SpikeGLX anatomy-overlay messages.
assert(profile.formatVersion==1 && strcmp(profile.subject,subject), ...
    'chipmunk_solo:AnatomySubject','Surgery plan subject does not match this session.');
probes=regexp(probeList,'\((\d+),(\d+),([^()]+)\)','tokens');
assert(numel(probes)==1,'chipmunk_solo:AnatomyProbe', ...
    'Requires exactly one neural probe; XIO-only acquisition has no anatomy overlay.');
probeId=str2double(probes{1}{1});nShanks=str2double(probes{1}{2});
assert(nShanks==profile.nShanks && nShanks==4 && startsWith(probes{1}{3},'NP2'), ...
    'chipmunk_solo:AnatomyGeometry','Connected probe does not match the four-shank NP2 surgery plan.');
assert(strcmp(profile.placementKind,'surgery plan'));
assert(~isempty(regexp(profile.provenance.sourceSHA256,'^[0-9a-fA-F]{64}$','once')));
assert(numel(profile.shanks)==nShanks && isequal(sort([profile.shanks.shankId]),0:nShanks-1));
commands=cell(1,nShanks);
for k=1:nShanks
    shank=profile.shanks(k);segments=shank.segments;
    assert(~isempty(segments));
    command=sprintf('[%d,%d]',probeId,shank.shankId);previous=0;
    for j=1:numel(segments)
        r=segments(j);rgb=r.rgb(:)';
        assert(isfinite(r.startUm) && isfinite(r.endUm) && abs(r.startUm-previous)<1e-3 && ...
            r.endUm>r.startUm && r.endUm<=20000,'Invalid or noncontiguous anatomy interval');
        assert(numel(rgb)==3 && all(isfinite(rgb)) && all(rgb>=0 & rgb<=255 & rgb==round(rgb)));
        assert(~isempty(regexp(r.region,'^[A-Za-z0-9_./ -]+$','once')));
        command=[command sprintf('(%.3f,%.3f,%d,%d,%d,%s)',r.startUm,r.endUm,rgb,r.region)]; %#ok<AGROW>
        previous=r.endUm;
    end
    commands{k}=command;
end
end
