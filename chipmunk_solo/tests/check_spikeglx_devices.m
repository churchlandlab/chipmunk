function check_spikeglx_devices()
root=fileparts(fileparts(mfilename('fullpath')));oldPath=path;
cleanup=onCleanup(@() path(oldPath));addpath(fullfile(root,'Functions','Utilities'));
rows=spikeglxDeviceRows('');assert(size(rows,1)==5 && isempty(spikeglxDeviceSelection(rows)));
for mask=1:31
    rows(:,1)=num2cell(logical(bitget(mask,1:5)'));
    selection=spikeglxDeviceSelection(rows);
    assert(isequal(rows,spikeglxDeviceRows(selection)),'OneBox checkbox round trip failed');
end
assert(strcmp(spikeglxDeviceSelection(spikeglxDeviceRows('(20,1,2)(20,2,1)(20,obx)')), ...
    '(20,1,2)(20,2,1)(20,obx)'));
assert(strcmp(spikeglxDeviceSelection(spikeglxDeviceRows('(40,1,1)')),'(40,1,1)'));
assert(size(spikeglxDeviceRows('(2,4,2)'),1)==8);
rows=spikeglxDeviceRows('(20,1,1)');
bad=rows;bad{1,2}=19;reject(bad);
bad=rows;bad{1,3}='3';reject(bad);
bad=rows;bad{1,4}=3;reject(bad);
bad=rows;bad{1,2}=40;bad{1,3}='XIO';reject(bad);
reject([rows;rows(1,:)]);
fprintf('PASS: all 31 OneBox selections, dock/XIO/SIM encoding and invalid addresses\n');
end
function reject(rows)
try,spikeglxDeviceSelection(rows);error('Test:Accepted','Invalid devices accepted');
catch e,assert(~strcmp(e.identifier,'Test:Accepted'));end
end
