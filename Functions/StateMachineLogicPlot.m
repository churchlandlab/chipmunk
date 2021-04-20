function varargout = StateMachineLogicPlot(sma, AxesHandle);
%varargout = StateMachineLogicPlot(sma);
%varargout = StateMachineLogicPlot(sma, AxesHandle);
%   
%Function to graphically represent the flow thorugh the different states
%within the provided state matrix.
%
%INPUTS:
%-sma(mandatory): Constructed state matrix
%-AxesHandle (optional): Handle of the axes the structure should be plotted
%                        to.
%
%OUTPUT:
%-varargout{1}: A digraph object containing the nodes and the edges of the
%               directed state transition graph.
%-varargout{2}: The handles to the state logic plot when AxesHandle has not
%               been provided and a new figure is created.
%
% LO, 1/5/2021
%--------------------------------------------------------------------------

%% Find the transitions
adjMat = zeros(length(sma.StateNames)); %create empty adjacency matrix

for j=1:length(sma.StateTimerMatrix) %Find the state switches when the timers are up
    if sma.StateTimerMatrix(j) > 0 && sma.StateTimerMatrix(j) < max(sma.StateTimerMatrix) %last timer is the exit
        adjMat(j,sma.StateTimerMatrix(j)) = 1;
    end
end

for j=1:size(sma.InputMatrix,1) %Find the state switches with regard to certain events
    indx = find(sma.InputMatrix(j,:)~=j); %annyoingly in InputMatrix undefined rows just contain the row number instead of 0 or NaN!
    if ~isempty(indx)
        for k=1:length(indx)
            adjMat(j,sma.InputMatrix(j,indx(k))) = 1;
        end
    end
end

for j=1:length(adjMat) %remove self referencing
    adjMat(j,j) = 0;
end

varargout{1} = digraph(adjMat, sma.StateNames); %create a directed graph object
%% Plotting

if ~exist('AxesHandle') || isempty(AxesHandle)
    figure
    varargout{2} = plot(varargout{1});
else
    plot(varargout{1}, 'Parent', AxesHandle);
end

end

    