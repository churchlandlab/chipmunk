function LEDswitch()
% LEDswitch()
%
% Switches LEDs from all the different ports on or off outside of a state
% matrix. Each call just changes the state from the current state to the
% other.
%
% LO, 6/7/2021
%--------------------------------------------------------------------------

ManualOverride('OP',1); %Switch on LED on port 1,...
ManualOverride('OP',2);
ManualOverride('OP',3);
ManualOverride('OP',4);

end