function check_historical_equivalence(historyRoot,currentRoot)
% Matched-source comparison; prepare_historical_comparison.py builds the input folder.
% Requires three recorded sessions supplied separately; opens no rig devices.
global BpodSystem HistoricalCues
assert(isempty(BpodSystem),'HistoricalEquivalence:FreshSession', ...
    'Run in a fresh MATLAB session before starting Bpod.');
oldPath=path; oldFolder=pwd;
cleanup=onCleanup(@() restore(oldPath,oldFolder));
cd(historyRoot);
manifest=jsondecode(fileread(fullfile(historyRoot,'wrapper-manifest.json')));
recordFiles=dir(fullfile(historyRoot,'recordings','*.mat'));
expected={'GRB006_20240723_142451_chipmunk_DemonstratorAudiTask.mat', ...
    'GRB063_20261030_134253_chipmunk_VisualTask.mat', ...
    'GRB064_20261030_151009_chipmunk_VisualTask.mat'};
assert(isequal({recordFiles.name},expected), 'Supply the three documented recorded sessions.');
recordings=cell(1,numel(recordFiles));
for k=1:numel(recordFiles)
    f=load(fullfile(recordFiles(k).folder,recordFiles(k).name));
    recordings{k}=f.SessionData;
end
% Identical parameters/random seeds for all versions. Standard Poisson task.
s=recordings{1}.TrialSettings(1);
s.manipPreset='standard'; s.baseWait=.5;
seeds=[1 7 31]; rates=[4 12 20]; modes=[1 1; 2 1; 3 0; 3 1; 3 2]; extras=[0 .25 1.25];
results=struct();
for v=1:numel(manifest)
    label=manifest(v).label;
    selectVersion(label,historyRoot,currentRoot,oldPath);
    BpodSystem=struct('ProtocolSettings',s,'GUIHandles',struct());
    hashes={}; caseInfo=[];
    for seed=seeds
        for rate=rates
            for m=1:size(modes,1)
                for extra=extras
                    BpodSystem.ProtocolSettings.syncMultiSensory=modes(m,2);
                    BpodSystem.ProtocolSettings.extraStimDur=extra;
                    rng(seed,'twister');
                    signal=feval(['historical_stim_' label],rate,modes(m,1));
                    hashes{end+1}=sampleHash(signal); %#ok<AGROW>
                    caseInfo(end+1,:)=[seed rate modes(m,:) extra size(signal,2)]; %#ok<AGROW>
                end
            end
        end
    end
    results.(label).stimulusHashes=hashes;
    results.(label).stimulusCases=caseInfo;
    fprintf('STIMULI %s %d\n',label,numel(hashes));

    % State-machine commands with the same deterministic valve-calibration double.
    matrixCases={}; cueHashes={}; biasValues=[];
    for source=1:numel(recordings)
        settings=recordings{source}.TrialSettings(1);
        isVisual=all(recordings{source}.Modality==1);
        settings.baseWait=.5;
        if strcmp(label,'original') && ischar(settings.minWaitTime)
            settings.baseWait=1; % Original exponential task used one second.
        end
        BpodSystem.ProtocolSettings=settings;
        for seed=seeds
            for side=0:1
                rng(seed,'twister');
                assembler=assemblerFor(label,isVisual);
                [matrix,delays]=feval(assembler,side);
                matrixCases{end+1}=canonicalMatrix(matrix,false); %#ok<AGROW>
                results.(label).ledMatrices{numel(matrixCases)}=canonicalMatrix(matrix,true);
                HistoricalCues={};
                rng(seed,'twister');
                if nargin('generateTaskControlSounds')>7
                    generateTaskControlSounds(settings.goCueLoudness,settings.earlyPunishLoudness, ...
                        settings.earlyPunishTimeout,settings.wrongPunishLoudness, ...
                        settings.wrongPunishTimeout,settings.soundCalibrationModelParams,delays,[],[]);
                else
                    generateTaskControlSounds(settings.goCueLoudness,settings.earlyPunishLoudness, ...
                        settings.earlyPunishTimeout,settings.wrongPunishLoudness, ...
                        settings.wrongPunishTimeout,settings.soundCalibrationModelParams,delays);
                end
                cueHashes{end+1}=cellfun(@sampleHash,HistoricalCues(2:5),'UniformOutput',false); %#ok<AGROW>
            end
        end
    end
    results.(label).matrices=matrixCases;
    results.(label).cueHashes=cueHashes;
    % Same bias inputs across sources, including both outcomes/sides/modalities.
    for modality=1:3
        for side=0:1
            for outcome=0:1
                [mb,tb]=updateAntiBiasArrays([.2 .5 .8],reshape(linspace(.1,.9,8),2,2,2), ...
                    modality,side,outcome,1-side,side,outcome,10);
                p=getAntiBiasPLeft(tb,mb,modality,.75,side,outcome);
                biasValues(end+1,:)=[mb tb(:)' p]; %#ok<AGROW>
            end
        end
    end
    results.(label).biasValues=biasValues;
end
reference=results.current;
summary=struct();
labels=fieldnames(results);
for k=1:numel(labels)
    label=labels{k}; r=results.(label);
    matches=cellfun(@isequal,r.stimulusHashes,reference.stimulusHashes);
    matrixMatches=cellfun(@isequal,r.matrices,reference.matrices);
    ledMatches=cellfun(@isequal,r.ledMatrices,reference.ledMatrices);
    cueMatches=cellfun(@isequal,r.cueHashes,reference.cueHashes);
    summary.(label)=struct('stimulusCases',numel(matches),'identicalStimuli',sum(matches), ...
        'stateCases',numel(matrixMatches),'identicalCoreMatrices',sum(matrixMatches), ...
        'identicalFullMatrices',sum(ledMatches),'identicalCueSets',sum(cueMatches), ...
        'identicalBiasOutputs',isequaln(r.biasValues,reference.biasValues));
    fprintf('COMPARE %s stimuli=%d/%d core=%d/%d full=%d/%d cues=%d/%d bias=%d\n', ...
        label,sum(matches),numel(matches),sum(matrixMatches),numel(matrixMatches), ...
        sum(ledMatches),numel(ledMatches),sum(cueMatches),numel(cueMatches), ...
        summary.(label).identicalBiasOutputs);
    assert(all(matches),'Standard Poisson stimulus mismatch for %s',label);
    assert(all(cueMatches),'Task-control sound mismatch for %s',label);
    assert(summary.(label).identicalBiasOutputs,'Bias-update mismatch for %s',label);
end

% Recompute every saved active trial's classification from its recorded events.
classification={};
for labelCell={'current','solo_base','half_latest','original'}
    label=labelCell{1};
    selectVersion(label,historyRoot,currentRoot,oldPath);
    for source=1:numel(recordings)
        d=recordings{source}; n=numel(d.Modality);
        BpodSystem=struct('Data',struct('LeftSideRewardAmount',0,'RightSideRewardAmount',0));
        for trial=1:n
            BpodSystem.ProtocolSettings=d.TrialSettings(trial);
            visual=d.InterStimulusIntervalList{trial,1}; auditory=d.InterStimulusIntervalList{trial,2};
            isi=visual; if d.Modality(trial)==2, isi=auditory; end
            args={d.RawEvents.Trial{trial},trial,d.CorrectSide,d.TrialDelays(trial), ...
                d.ReviseChoiceFlag,d.Modality,d.StimulusDuration(trial), ...
                d.StimTrainDuration(trial),d.CategoryBoundary(trial),isi,visual,auditory};
            if nargin('retrieveTrialData')==14
                retrieveTrialData(args{:},d.TrialSettings(trial).stimBrightness,.025);
            else
                retrieveTrialData(args{:});
            end
        end
        active=BpodSystem.Data;
        fields={'OutcomeRecord','Rewarded','EarlyWithdrawal','DidNotChoose','DidNotInitiate', ...
            'ResponseSide','CorrectResponse','ValidTrials','ActualWaitTime', ...
            'LeftSideRewardAmount','RightSideRewardAmount'};
        differences={};
        for f=1:numel(fields)
            field=fields{f};
            if ~isequaln(active.(field),d.(field)),differences{end+1}=field;end %#ok<AGROW>
        end
        classification{end+1}=struct('label',label,'recording',recordFiles(source).name, ...
            'nTrials',n,'differencesFromSaved',{differences}); %#ok<AGROW>
        fprintf('RECORD %s %s n=%d differences=%s\n',label,recordFiles(source).name,n,strjoin(differences,','));
    end
end
% Original one-second exponential task matches after selecting baseWait=1
% and the LED-preserving MultipleModalitiesTask assembler.
selectVersion('original',historyRoot,currentRoot,oldPath);
originalMatrices={};
for seed=seeds
 for side=0:1
  settings=recordings{2}.TrialSettings(1); settings.minWaitTime='exp';
  BpodSystem.ProtocolSettings=settings;rng(seed,'twister');
  matrix=DemonstratorTaskSMA(side);originalMatrices{end+1}=canonicalMatrix(matrix,true);
 end
end
selectVersion('current',historyRoot,currentRoot,oldPath);
oneSecondMatches=0;idx=0;
for seed=seeds
 for side=0:1
  settings=recordings{2}.TrialSettings(1);settings.minWaitTime='exp';settings.baseWait=1;
  BpodSystem.ProtocolSettings=settings;rng(seed,'twister');
  matrix=MultipleModalitiesTaskSMA(side);idx=idx+1;
  oneSecondMatches=oneSecondMatches+isequal(originalMatrices{idx},canonicalMatrix(matrix,true));
 end
end
assert(oneSecondMatches==6);
staircase=struct();
for labelCell={'solo_base','half_latest','half_2024','original','ephys'}
 label=labelCell{1};rows=[];
 for initial=[.49 .5 .59 .6 1.09 1.1]
  for step=[0 .01 .05]
   for outcome=[-1 0 1 2]
    settings=struct('minWaitTime',initial,'minWaitTimeStep',step,'baseWait',.5);
    old=feval(['historical_step_' label],settings,outcome);
    new=historical_step_current(settings,outcome);
    if ~isequal(old.minWaitTime,new.minWaitTime) || ~isequal(old.minWaitTimeStep,new.minWaitTimeStep)
     rows(end+1,:)=[initial step outcome old.minWaitTime new.minWaitTime];
    end
   end
  end
 end
 staircase.(label)=rows;
end
assert(summary.solo_base.identicalCoreMatrices==18 && summary.solo_base.identicalFullMatrices==18);
assert(summary.half_latest.identicalCoreMatrices==18 && summary.half_latest.identicalFullMatrices==18);
assert(summary.half_2024.identicalCoreMatrices==18 && summary.half_2024.identicalFullMatrices==6);
assert(summary.original.identicalCoreMatrices==6);
assert(isempty(staircase.solo_base) && isempty(staircase.half_latest));
for k=1:numel(classification)
 assert(isempty(classification{k}.differencesFromSaved),'Recorded classification mismatch.');
end
report=struct('summary',summary,'classification',{classification}, ...
 'oneSecondFullMatrixMatches',oneSecondMatches,'staircaseDifferences',staircase);
fid=fopen(fullfile(historyRoot,'comparison-results.json'),'w');
fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
save(fullfile(historyRoot,'comparison-results.mat'),'results','summary','classification');
disp('HISTORICAL_COMPARISON_FINISHED');
end

function selectVersion(label,historyRoot,currentRoot,originalPath)
path(originalPath);
if strcmp(label,'current'), folder=fullfile(currentRoot,'Functions');
elseif strcmp(label,'ephys'),folder=fullfile(historyRoot,'sources','half_latest','Functions');
else,folder=fullfile(historyRoot,'sources',label,'Functions');end
addpath(genpath(folder));
addpath(fullfile(historyRoot,'generated'));
addpath(fullfile(historyRoot,'capture'),'-begin');
clear poissonStimulusTrain twoIntervalStimulusTrain createVisualStimSignal createAuditoryStimSignal
clear generate_random_delay generateTaskControlSounds resolveTrialStimulusParams ensureStimulusManipulationSettings
clear VisualTaskSMA MultipleModalitiesTaskSMA MultiTaskSMA DemonstratorTaskSMA retrieveTrialData
clear drawStimModality findStimRate updateAntiBiasArrays getAntiBiasPLeft
end

function assembler=assemblerFor(label,isVisual)
if strcmp(label,'original'),assembler='DemonstratorTaskSMA';return;end
if isVisual,assembler='VisualTaskSMA';return;end
if strcmp(label,'half_2024'),assembler='MultiTaskSMA';else,assembler='MultipleModalitiesTaskSMA';end
end

function value=canonicalMatrix(matrix,includePWM)
value=struct();
for k=1:numel(matrix.States)
    state=matrix.States{k};
    actions=state.OutputActions;
    if ~includePWM && ~isempty(actions)
        keep=~startsWith(string(actions(1:2:end)),'PWM');
        pairs=reshape(actions,2,[]); actions=reshape(pairs(:,keep),1,[]);
    end
    value.(state.Name)=struct('timer',state.Timer, ...
        'conditions',{sortPairs(state.StateChangeConditions)},'outputs',{sortPairs(actions)});
end
value=orderfields(value);
end

function pairs=sortPairs(pairs)
if isempty(pairs),pairs={};return;end
p=reshape(pairs,2,[]);[~,idx]=sort(string(p(1,:)));pairs=reshape(p(:,idx),1,[]);
end

function hash=sampleHash(signal)
md=java.security.MessageDigest.getInstance('SHA-256');
if ~isempty(signal), md.update(typecast(double(signal(:)),'int8')); end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end

function restore(oldPath,oldFolder)
global BpodSystem HistoricalCues
BpodSystem=[];HistoricalCues=[];
path(oldPath);cd(oldFolder);
end
