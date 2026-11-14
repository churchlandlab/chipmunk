function check_trace_timer_pause()
% The SpikeGLX trace timer is off while a trial runs and back on after, also after an error.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
fakeDir = tempname; mkdir(fakeDir);
cleanup = onCleanup(@() restore(oldPath, fakeDir));
addpath(fullfile(root, 'Functions', 'Utilities'));
fid = fopen(fullfile(fakeDir, 'RunStateMatrix.m'), 'w');
fprintf(fid, ['function events = RunStateMatrix()\n' ...
    'global TraceTest\n' ...
    'events = strcmp(get(timerfind(''Name'',''SpikeGLXTraces''),''Running''),''off'');\n' ...
    'if TraceTest.fail, error(''TraceTest:Fail'',''injected''); end\n' ...
    'end\n']);
fclose(fid);
addpath(fakeDir, '-begin');
global TraceTest
t = timer('Name', 'SpikeGLXTraces', 'Period', 0.5, 'ExecutionMode', 'fixedSpacing', 'TimerFcn', @(~,~) []);
timerCleanup = onCleanup(@() delete(t));
start(t);
TraceTest.fail = false;
assert(runTrialStateMatrix(), 'Trace timer ran during the trial.');
assert(strcmp(t.Running, 'on'), 'Trace timer did not resume.');
TraceTest.fail = true;
try
    runTrialStateMatrix();
    error('Expected the injected failure.');
catch ME
    assert(strcmp(ME.identifier, 'TraceTest:Fail'), ME.message);
end
assert(strcmp(t.Running, 'on'), 'Trace timer did not resume after an error.');
stop(t);
TraceTest.fail = false;
assert(runTrialStateMatrix() && strcmp(t.Running, 'off'), 'A stopped timer was started.');
disp('PASS: trace timer paused during trials');
end

function restore(oldPath, fakeDir)
path(oldPath);
rmdir(fakeDir, 's');
end
