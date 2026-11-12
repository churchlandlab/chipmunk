function [combos, labels] = longPulseCombinations()
% Same 15:25 pulse:gap as standard. Only scales that tile a 1 s train.
% 2x (30/50) is 80 ms and does not divide 1 s; next legal scale is 5x.
combos = [
    75 125 5
    ];
labels = {
    '75 / 125 ms (5x)'
    };
end
