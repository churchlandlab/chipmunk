function check_chipmunk_endurance(outputFolder)
% Real 1,000-trial emulator run; short behavioral holds, full waveform/GUI/save path.
check_chipmunk_replay_session(outputFolder, {'VisualTask'}, '', 1000);
end
