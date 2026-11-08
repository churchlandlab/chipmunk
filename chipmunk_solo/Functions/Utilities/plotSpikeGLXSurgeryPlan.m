function bands = plotSpikeGLXSurgeryPlan(ax,profile,onSelect)
% Planned atlas regions along each shank, measured upward from the probe tip.
if nargin<3,onSelect=[];end
assert(strcmp(profile.placementKind,'surgery plan') && profile.nShanks==4 && ...
    isequal(sort([profile.shanks.shankId]),0:3),'Invalid four-shank surgery plan.');
cla(ax);hold(ax,'on');bands=gobjects(0);brainEnd=0;fullEnd=0;
for k=1:numel(profile.shanks)
    shank=profile.shanks(k);previous=0;
    for j=1:numel(shank.segments)
        r=shank.segments(j);rgb=r.rgb(:)'/255;
        assert(isfinite(r.startUm) && isfinite(r.endUm) && ...
            abs(r.startUm-previous)<1e-3 && r.endUm>r.startUm && r.endUm<=20000 && ...
            numel(rgb)==3 && all(isfinite(rgb)) && all(rgb>=0 & rgb<=1),'Invalid atlas region.');
        x=shank.shankId+[-.34 .34 .34 -.34];
        y=[r.startUm r.startUm r.endUm r.endUm];
        band=patch(ax,x,y,rgb,'EdgeColor',[.45 .45 .45],'LineWidth',.3, ...
            'UserData',struct('shankId',shank.shankId,'region',r));
        if ~isempty(onSelect),set(band,'ButtonDownFcn',@(~,~) onSelect(shank.shankId,r));end
        bands(end+1)=band; %#ok<AGROW>
        if ~strcmp(r.region,'outside'),brainEnd=max(brainEnd,r.endUm);end
        fullEnd=max(fullEnd,r.endUm);previous=r.endUm;
    end
end
limit=fullEnd;
if brainEnd>0,limit=min(fullEnd,500*ceil((brainEnd+250)/500));end
limit=max(limit,min(fullEnd,3000));
for k=1:numel(bands)
    data=bands(k).UserData;r=data.region;
    if r.endUm-r.startUm>=limit*.035 && r.endUm<=limit
        color=[0 0 0];if mean(bands(k).FaceColor)<.4,color=[1 1 1];end
        text(ax,data.shankId,mean([r.startUm r.endUm]),r.region, ...
            'HorizontalAlignment','center','FontSize',8,'Color',color, ...
            'Interpreter','none','HitTest','off');
    end
end
if fullEnd>=2500
    for shank=0:3
        plot(ax,shank+[-.34 .34],[2500 2500],'k--','LineWidth',1.5, ...
            'Tag','BankBoundary','HitTest','off');
    end
end
hold(ax,'off');set(ax,'YDir','normal','XLim',[-.6 3.6],'YLim',[0 limit], ...
    'XTick',0:3,'XTickLabel',{'Shank 0','Shank 1','Shank 2','Shank 3'},'FontSize',8);
ylabel(ax,'Distance from tip (µm)');title(ax,[profile.subject ' — planned anatomy'],'Interpreter','none');
set(ax,'UserData',profile);
end
