function selection = spikeglxDeviceSelection(rows)
% Encode only checked GUI rows into SpikeGLX's native device addresses.
selection='';addresses={};
for k=1:size(rows,1)
    if ~rows{k,1},continue;end
    slot=rows{k,2};port=rows{k,3};dock=rows{k,4};
    assert(isnumeric(slot) && isscalar(slot) && ismember(slot,[2:18 20:31 40:41]),'Invalid SpikeGLX slot.');
    if strcmpi(port,'XIO')
        assert(slot>=20 && slot<=31,'XIO requires a OneBox slot (20–31).');
        address=sprintf('(%d,obx)',slot);
    else
        port=str2double(port);nPorts=4;if slot>=20 && slot<=31,nPorts=2;end
        assert(isscalar(port) && ismember(port,1:nPorts) && isnumeric(dock) && ...
            isscalar(dock) && ismember(dock,1:2),'Invalid probe port or dock.');
        address=sprintf('(%d,%d,%d)',slot,port,dock);
    end
    assert(~ismember(address,addresses),'A device address is selected more than once.');
    addresses{end+1}=address;selection=[selection address]; %#ok<AGROW>
end
end
