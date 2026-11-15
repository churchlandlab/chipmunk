function stimulusModality = drawStimModality;
% stimulusModality = drawStimModality
%
% Tiny function to draw the stimulus modality for the next trial. The
% proportion of visual and auditory only trials are taken directly from
% BpodSystem.
%
% OUTPUT: -stimulusModality: Modality record with 1 being visual, 2 being
%                            auditory and 3 multisensory trials.
%
% LO, 4/2/2021
%
%--------------------------------------------------------------------------
global BpodSystem

stimulusModality = [];
drawM = rand; %Generate a ranom number between 0 and 1

    if drawM < BpodSystem.ProtocolSettings.propOnlyVisual
    stimulusModality = 1; %Visual modality code is 1
    elseif drawM < BpodSystem.ProtocolSettings.propOnlyVisual + BpodSystem.ProtocolSettings.propOnlyAuditory
        stimulusModality = 2; %Auditory modality code is 2
    else
    stimulusModality = 3; %Multi-sensory trials are identified by number 3
    end
    
end