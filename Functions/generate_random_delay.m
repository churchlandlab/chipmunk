lambda = 1;
minimum = 1;
maximum = 10;
random_delay = [];
for k=1:1000
if ~((minimum == 0) && (maximum ==0))
    x = -log(rand)/lambda;
    random_delay(k) = mod(x, maximum - minimum) + minimum;
end
end
