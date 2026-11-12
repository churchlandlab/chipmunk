function rows = spikeglxDeviceRows(selection)
% Expand selected addresses into checkboxes for each slot's ports and docks.
selection=regexprep(selection,'\s','');
tokens=regexp(selection,'\((\d+),(obx|\d+)(?:,(\d+))?\)','tokens');
slots=[];
for k=1:numel(tokens),slots(end+1)=str2double(tokens{k}{1});end
slots=unique(slots,'stable');if isempty(slots),slots=20;end
rows=cell(0,4);
for slot=slots
    nPorts=4;if slot>=20 && slot<=31,nPorts=2;end
    for port=1:nPorts
        for dock=1:2
            selected=contains(selection,sprintf('(%d,%d,%d)',slot,port,dock));
            rows(end+1,:)={selected,slot,num2str(port),dock};
        end
    end
    if slot>=20 && slot<=31
        rows(end+1,:)={contains(selection,sprintf('(%d,obx)',slot)),slot,'XIO',[]};
    end
end
end
