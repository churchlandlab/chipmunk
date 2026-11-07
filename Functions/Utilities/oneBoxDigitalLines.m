function [levels, labels] = oneBoxDigitalLines(stream)
% OneBox XD contains 12 input bits; SY bit 6 is the hardware sync signal.
levels = false(size(stream.data,1),0);
labels = {};
xd = find(stream.channels == stream.nXA,1);
if stream.nDW > 0 && ~isempty(xd)
    word = typecast(int16(stream.data(:,xd)), 'uint16');
    for bit = 0:11
        levels = [levels, bitget(word,bit+1) ~= 0];
        labels{end+1} = sprintf('XD%d',bit);
    end
end
sy = find(stream.channels == stream.nXA + stream.nDW,1);
if stream.nSY > 0 && ~isempty(sy)
    word = typecast(int16(stream.data(:,sy)), 'uint16');
    levels = [levels, bitget(word,7) ~= 0];
    labels{end+1} = 'Sync (SY6)';
end
end
